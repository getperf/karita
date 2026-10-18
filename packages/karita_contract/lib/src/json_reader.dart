/// 重複キー検出付きの JSON デコード（字句走査）。
///
/// `dart:convert` の `jsonDecode` には重複キーを検出するフックが無く、素直に使うと
/// `{"a":1,"a":2}` を後勝ちで黙って通す。後勝ちで読むと、宣言された `payloadHash` と一致した
/// まま壊れた入力が通る経路が開く。デコード後の
/// 結果からは復元できない情報なので、字句を走査する読み取りを自前で持つ。
///
/// `jsonDecode` を使わないもう一つの理由は、Python の `json.loads` と同じ**整数と浮動小数の
/// 読み分け**を保証するためである。小数点も指数も持たない数は整数（`int`、64bit を超える場合は
/// `BigInt`）、それ以外は `double` に読む。この区別が正準化の float 拒否（`canonical-float`）と
/// 整数上限（`canonical-int-range`）の入口になる。
library;

import 'errors.dart';

/// 外から来た JSON を読む。**重複キーを拒否する。**
///
/// 構文エラーは code `json`、同一オブジェクト内のキー重複は code `json-duplicate-key` で
/// `SyncDataError` を投げる。値のツリーは `Map<String, Object?>` / `List<Object?>` /
/// `String` / `int` / `BigInt` / `double` / `bool` / `null` で返す。
Object? loadsJson(String text, {String label = 'JSON'}) {
  final parser = _Parser(text, label);
  return parser.parse();
}

class _Parser {
  final String _s;
  final String _label;
  int _i = 0;

  _Parser(this._s, this._label);

  Object? parse() {
    _skipWs();
    final value = _readValue();
    _skipWs();
    if (_i != _s.length) {
      _fail('末尾に余分な文字があります');
    }
    return value;
  }

  Never _fail(String why) {
    throw SyncDataError('$_label を読めません: $why（位置 $_i）', code: 'json');
  }

  Never _duplicate(String key) {
    throw SyncDataError(
      '$_label にキーの重複があります: "$key"。'
      '後勝ちで読むと、宣言された payloadHash と一致したまま壊れた入力が通ります。',
      code: 'json-duplicate-key',
    );
  }

  bool get _atEnd => _i >= _s.length;

  int get _cur => _s.codeUnitAt(_i);

  void _skipWs() {
    while (!_atEnd) {
      final c = _cur;
      if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
        _i++;
      } else {
        break;
      }
    }
  }

  Object? _readValue() {
    if (_atEnd) _fail('値がありません');
    final c = _cur;
    switch (c) {
      case 0x7B: // {
        return _readObject();
      case 0x5B: // [
        return _readArray();
      case 0x22: // "
        return _readString();
      case 0x74: // t
        return _readLiteral('true', true);
      case 0x66: // f
        return _readLiteral('false', false);
      case 0x6E: // n
        return _readLiteral('null', null);
      default:
        if (c == 0x2D || (c >= 0x30 && c <= 0x39)) {
          return _readNumber();
        }
        _fail('予期しない文字');
    }
  }

  Object? _readLiteral(String word, Object? value) {
    if (_i + word.length > _s.length || _s.substring(_i, _i + word.length) != word) {
      _fail('リテラル $word を期待しました');
    }
    _i += word.length;
    return value;
  }

  Map<String, Object?> _readObject() {
    _i++; // {
    final result = <String, Object?>{};
    _skipWs();
    if (!_atEnd && _cur == 0x7D) {
      _i++;
      return result;
    }
    while (true) {
      _skipWs();
      if (_atEnd || _cur != 0x22) _fail('オブジェクトのキーは文字列である必要があります');
      final key = _readString();
      _skipWs();
      if (_atEnd || _cur != 0x3A) _fail('キーの後に : が必要です');
      _i++; // :
      _skipWs();
      final value = _readValue();
      if (result.containsKey(key)) _duplicate(key);
      result[key] = value;
      _skipWs();
      if (_atEnd) _fail('オブジェクトが閉じていません');
      final c = _cur;
      if (c == 0x2C) {
        _i++; // ,
        continue;
      }
      if (c == 0x7D) {
        _i++; // }
        return result;
      }
      _fail(', か } を期待しました');
    }
  }

  List<Object?> _readArray() {
    _i++; // [
    final result = <Object?>[];
    _skipWs();
    if (!_atEnd && _cur == 0x5D) {
      _i++;
      return result;
    }
    while (true) {
      _skipWs();
      result.add(_readValue());
      _skipWs();
      if (_atEnd) _fail('配列が閉じていません');
      final c = _cur;
      if (c == 0x2C) {
        _i++;
        continue;
      }
      if (c == 0x5D) {
        _i++;
        return result;
      }
      _fail(', か ] を期待しました');
    }
  }

  String _readString() {
    _i++; // opening "
    final sb = StringBuffer();
    while (true) {
      if (_atEnd) _fail('文字列が閉じていません');
      final c = _cur;
      _i++;
      if (c == 0x22) {
        return sb.toString();
      }
      if (c == 0x5C) {
        if (_atEnd) _fail('エスケープが閉じていません');
        final e = _cur;
        _i++;
        switch (e) {
          case 0x22:
            sb.writeCharCode(0x22);
            break;
          case 0x5C:
            sb.writeCharCode(0x5C);
            break;
          case 0x2F:
            sb.writeCharCode(0x2F);
            break;
          case 0x62:
            sb.writeCharCode(0x08);
            break;
          case 0x66:
            sb.writeCharCode(0x0C);
            break;
          case 0x6E:
            sb.writeCharCode(0x0A);
            break;
          case 0x72:
            sb.writeCharCode(0x0D);
            break;
          case 0x74:
            sb.writeCharCode(0x09);
            break;
          case 0x75:
            sb.writeCharCode(_readHex4());
            break;
          default:
            _fail('未知のエスケープ');
        }
      } else if (c < 0x20) {
        _fail('文字列に生の制御文字があります');
      } else {
        sb.writeCharCode(c);
      }
    }
  }

  int _readHex4() {
    if (_i + 4 > _s.length) _fail('\\u の後に16進4桁が必要です');
    var value = 0;
    for (var k = 0; k < 4; k++) {
      final c = _s.codeUnitAt(_i);
      _i++;
      int digit;
      if (c >= 0x30 && c <= 0x39) {
        digit = c - 0x30;
      } else if (c >= 0x61 && c <= 0x66) {
        digit = c - 0x61 + 10;
      } else if (c >= 0x41 && c <= 0x46) {
        digit = c - 0x41 + 10;
      } else {
        _fail('\\u の後に16進4桁が必要です');
      }
      value = value * 16 + digit;
    }
    return value;
  }

  Object _readNumber() {
    final start = _i;
    var isDouble = false;
    if (!_atEnd && _cur == 0x2D) _i++;
    while (!_atEnd && _cur >= 0x30 && _cur <= 0x39) {
      _i++;
    }
    if (!_atEnd && _cur == 0x2E) {
      isDouble = true;
      _i++;
      while (!_atEnd && _cur >= 0x30 && _cur <= 0x39) {
        _i++;
      }
    }
    if (!_atEnd && (_cur == 0x65 || _cur == 0x45)) {
      isDouble = true;
      _i++;
      if (!_atEnd && (_cur == 0x2B || _cur == 0x2D)) _i++;
      while (!_atEnd && _cur >= 0x30 && _cur <= 0x39) {
        _i++;
      }
    }
    final literal = _s.substring(start, _i);
    if (literal.isEmpty || literal == '-') _fail('数値が読めません');
    if (isDouble) {
      final d = double.tryParse(literal);
      if (d == null) _fail('数値が読めません: $literal');
      return d;
    }
    // 小数点も指数も無い整数。64bit に収まれば int、収まらなければ BigInt。
    // BigInt を返すのは、2^63 を超える整数を「桁あふれ」ではなく整数として扱い、
    // 正準化の整数上限（canonical-int-range）で捕まえるためである。
    final asInt = int.tryParse(literal);
    if (asInt != null) return asInt;
    return BigInt.parse(literal);
  }
}
