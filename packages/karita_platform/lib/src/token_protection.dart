/// 保存する token の保護。Windows はユーザー単位の DPAPI を薄い FFI で呼ぶ。
///
/// **守れる範囲は「同じ Windows ユーザー」までである。** 同じユーザーで動く他のプログラム、
/// プロセスメモリ、台帳そのものは守らない。DPAPI はパッケージ identity でも分離されない —
/// 通常実行と MSIX 実行で互いの blob を開けた（`非公開資料:2026-10-18-windows-token-protection-probe.md`）。
///
/// **`CRYPTPROTECT_LOCAL_MACHINE` を使わない。** 付けると同じ PC の他ユーザーでも開ける。
/// **`CRYPTPROTECT_UI_FORBIDDEN` を常に付ける。** 背景同期の途中で確認画面を出さない。
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// 保護と解除の口。**試験と Windows 以外のために差し替えられる形にする。**
abstract interface class TokenProtector {
  /// 失敗したら [TokenProtectionException] を投げる。**平文を返さない。**
  Uint8List protect(Uint8List plain);

  /// 開けなければ [TokenProtectionException] を投げる。
  Uint8List unprotect(Uint8List sealed);

  /// この端末の既定。Windows は DPAPI、それ以外は [UnavailableTokenProtector]。
  ///
  /// **Windows 以外で平文へ落とさない。** 本番で `TokenStore` を使うのは Windows だけであり、
  /// 他の端末で呼ばれたなら組み立ての誤りである。
  factory TokenProtector.platform() => Platform.isWindows
      ? DpapiTokenProtector()
      : const UnavailableTokenProtector();
}

/// 保護・解除に失敗した。**値を持たない。**
///
/// [win32Error] は参考値である。Dart FFI の `GetLastError` は上書きされることがあり、
/// entropy 違いで 0 が返った（probe で実測）。**原因の分類に使わない。**
class TokenProtectionException implements Exception {
  final String operation;
  final int? win32Error;

  const TokenProtectionException(this.operation, [this.win32Error]);

  @override
  String toString() =>
      'TokenProtectionException($operation'
      '${win32Error == null ? '' : ', win32=$win32Error'})';
}

class UnavailableTokenProtector implements TokenProtector {
  const UnavailableTokenProtector();

  @override
  Uint8List protect(Uint8List plain) =>
      throw const TokenProtectionException('protect-unavailable');

  @override
  Uint8List unprotect(Uint8List sealed) =>
      throw const TokenProtectionException('unprotect-unavailable');
}

/// ユーザー単位 DPAPI。
///
/// アプリ固有の entropy を付ける。**秘密ではない**（バイナリに入る）。同じユーザーの別アプリが
/// blob を拾って `CryptUnprotectData` を呼んだだけでは開けない、という段差を付けるだけである。
/// **変えると既存の保存が開けなくなる。** 変えるときは保存形式の版を上げる。
class DpapiTokenProtector implements TokenProtector {
  static final Uint8List _entropy = Uint8List.fromList(
    utf8.encode('karita.token-store.v1'),
  );

  @override
  Uint8List protect(Uint8List plain) => _dpapi(
    'CryptProtectData',
    plain,
    (input, entropy, output) => _cryptProtectData(
      input,
      nullptr,
      entropy,
      nullptr,
      nullptr,
      _cryptProtectUiForbidden,
      output,
    ),
  );

  @override
  Uint8List unprotect(Uint8List sealed) => _dpapi(
    'CryptUnprotectData',
    sealed,
    (input, entropy, output) => _cryptUnprotectData(
      input,
      nullptr,
      entropy,
      nullptr,
      nullptr,
      _cryptProtectUiForbidden,
      output,
    ),
  );
}

const int _cryptProtectUiForbidden = 0x1;

final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;
  external Pointer<Uint8> pbData;
}

typedef _ProtectNative =
    Int32 Function(
      Pointer<_DataBlob>,
      Pointer<Utf16>,
      Pointer<_DataBlob>,
      Pointer<Void>,
      Pointer<Void>,
      Uint32,
      Pointer<_DataBlob>,
    );
typedef _Protect =
    int Function(
      Pointer<_DataBlob>,
      Pointer<Utf16>,
      Pointer<_DataBlob>,
      Pointer<Void>,
      Pointer<Void>,
      int,
      Pointer<_DataBlob>,
    );
typedef _UnprotectNative =
    Int32 Function(
      Pointer<_DataBlob>,
      Pointer<Pointer<Utf16>>,
      Pointer<_DataBlob>,
      Pointer<Void>,
      Pointer<Void>,
      Uint32,
      Pointer<_DataBlob>,
    );
typedef _Unprotect =
    int Function(
      Pointer<_DataBlob>,
      Pointer<Pointer<Utf16>>,
      Pointer<_DataBlob>,
      Pointer<Void>,
      Pointer<Void>,
      int,
      Pointer<_DataBlob>,
    );

// **遅延して開く。** Windows 以外で import しただけで落ちないようにする。
final DynamicLibrary _crypt32 = DynamicLibrary.open('crypt32.dll');
final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

// **leaf にする。** leaf でない呼出しは戻りで VM が他の Win32 API を呼び、エラー番号が
// 上書きされうる。leaf でも完全には防げなかったので、番号は参考値に留める。
final _Protect _cryptProtectData = _crypt32
    .lookupFunction<_ProtectNative, _Protect>('CryptProtectData', isLeaf: true);
final _Unprotect _cryptUnprotectData = _crypt32
    .lookupFunction<_UnprotectNative, _Unprotect>(
      'CryptUnprotectData',
      isLeaf: true,
    );
final Pointer<Void> Function(Pointer<Void>) _localFree = _kernel32
    .lookupFunction<
      Pointer<Void> Function(Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>)
    >('LocalFree', isLeaf: true);
final int Function() _getLastError = _kernel32
    .lookupFunction<Uint32 Function(), int Function()>(
      'GetLastError',
      isLeaf: true,
    );

/// 出力 blob は DPAPI が `LocalAlloc` で確保するので、写した後に 0 で埋めて `LocalFree` する。
/// 入力側も解放前に 0 で埋める。**痕跡を減らすだけで、メモリ上の保護は約束しない**（Dart の
/// `String` は消せない）。
Uint8List _dpapi(
  String operation,
  Uint8List data,
  int Function(Pointer<_DataBlob>, Pointer<_DataBlob>, Pointer<_DataBlob>)
  invoke,
) {
  final input = _blobOf(data);
  final entropy = _blobOf(DpapiTokenProtector._entropy);
  final output = calloc<_DataBlob>();
  try {
    if (invoke(input, entropy, output) == 0) {
      throw TokenProtectionException(operation, _getLastError());
    }
    final out = output.ref.pbData.asTypedList(output.ref.cbData);
    try {
      return Uint8List.fromList(out);
    } finally {
      out.fillRange(0, out.length, 0);
      _localFree(output.ref.pbData.cast());
    }
  } finally {
    _freeBlob(input);
    _freeBlob(entropy);
    calloc.free(output);
  }
}

Pointer<_DataBlob> _blobOf(Uint8List bytes) {
  final blob = calloc<_DataBlob>();
  // 0 バイトでも有効なポインタを渡す。
  final buffer = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
  buffer.asTypedList(bytes.length).setAll(0, bytes);
  blob.ref
    ..cbData = bytes.length
    ..pbData = buffer;
  return blob;
}

void _freeBlob(Pointer<_DataBlob> blob) {
  blob.ref.pbData.asTypedList(blob.ref.cbData).fillRange(0, blob.ref.cbData, 0);
  calloc.free(blob.ref.pbData);
  calloc.free(blob);
}
