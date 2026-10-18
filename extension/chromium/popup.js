// 送信元の選択だけを行う。ISBN の受理と予約の記録は karita 側で判定する。
(async () => {
  const api = globalThis.browser || globalThis.chrome;
  const notice = document.getElementById('notice');
  const grant = document.getElementById('grant');
  const parent = document.getElementById('parent');
  const current = document.getElementById('current');
  const lending = document.getElementById('lending');
  const mypage = document.getElementById('mypage');
  const retry = document.getElementById('retry');
  const origin = 'https://calil.jp/*';
  const delivery = (url, purpose) => 'karita://share?url=' + encodeURIComponent(url) +
    (purpose ? '&purpose=' + purpose : '');

  // **リンクの既定動作で開かない。** Firefox はポップアップ内のリンクを新しいタブで開き、
  // karita:// のタブだけが残って karita が起動しなかった（2026-10-13）。自動送信と同じく
  // ポップアップ自身を移動させる。
  for (const link of [parent, current, lending, mypage, retry]) {
    link.addEventListener('click', (event) => {
      if (!link.href.startsWith('karita:')) return;
      event.preventDefault();
      location.href = link.href;
    });
  }

  function calilBookPage(raw) {
    try {
      const url = new URL(raw);
      return url.protocol === 'https:' && url.hostname === 'calil.jp' &&
        !url.port && url.pathname.startsWith('/book/') && raw.length <= 2048;
    } catch {
      return false;
    }
  }

  // **ホストの完全一致だけを見る。ISBN の規則は書かない**（判定は karita 側）。
  function amazonPage(raw) {
    try {
      const url = new URL(raw);
      return url.protocol === 'https:' && !url.port &&
        (url.hostname === 'www.amazon.co.jp' || url.hostname === 'amazon.co.jp');
    } catch {
      return false;
    }
  }

  // **karita ガイドの連携確認ページ。** 押したらそのまま送る（0.6.0、2026-10-15）。
  // 親タブの探索に入れると、karita から開いたタブでも親があるので、要らないカーリルの
  // 読み取り許可を求めてしまう。ホストとパスの完全一致で見る（判定の正本は karita 側の
  // `HandoffLinkCheck`）。
  function linkCheckPage(raw) {
    try {
      const url = new URL(raw);
      return url.protocol === 'https:' && !url.port &&
        url.hostname === 'karita.getperf.net' &&
        ['/extensions/check', '/extensions/check/', '/extensions/check/index.html']
          .includes(url.pathname);
    } catch {
      return false;
    }
  }

  function showCurrent(url) {
    current.href = delivery(url);
    current.hidden = false;
  }

  // **openerTabId の検出結果に関わらず常に有効にする。** 図書館サイトへ直接アクセスした
  // 場合（親タブが無い・カーリルではない）でも、貸出し・マイページの操作は妨げない
  // （決定C' 2026-09-29）。
  function showPurposeLinks(url) {
    lending.href = delivery(url, 'lending');
    lending.hidden = false;
    mypage.href = delivery(url, 'mypage_url');
    mypage.hidden = false;
  }

  async function inspectParent(tab, url) {
    const allowed = await api.permissions.contains({origins: [origin]});
    if (!allowed) {
      notice.textContent = '元のカーリルタブを読む権限がありません。許可後にもう一度確認できます。';
      grant.hidden = false;
      showCurrent(url);
      return;
    }

    let opener;
    try {
      opener = await api.tabs.get(tab.openerTabId);
    } catch {
      notice.textContent = '開いた元のタブを取得できません。閉じられた可能性があります。';
      showCurrent(url);
      return;
    }
    if (!opener.url) {
      notice.textContent = '元のタブの URL を読めません。拡張のカーリルへのサイトアクセスを確認してください。';
      showCurrent(url);
      return;
    }
    if (!calilBookPage(opener.url)) {
      notice.textContent = '開いた元のタブはカーリルの書籍ページではありません。';
      showCurrent(url);
      return;
    }

    notice.textContent = '元のカーリル書籍を見つけました。送る URL を選んでください。';
    parent.textContent = `元のカーリル書籍（${new URL(opener.url).pathname}）を karita に送る`;
    parent.href = delivery(opener.url);
    parent.hidden = false;
    showCurrent(url);
  }

  try {
    const [tab] = await api.tabs.query({active: true, currentWindow: true});
    const url = tab?.url || '';
    if (!/^https?:\/\//.test(url) || url.length > 2048) {
      notice.textContent = url.length > 2048
        ? 'URL が長すぎます。' : 'Web ページのタブで押してください。';
      return;
    }

    // Amazon は**クエリとフラグメントを落としてから**送る。検索語・追跡値を karita へ渡さない。
    // 判定はパスだけで足りる（0.5.0）。
    const amazon = amazonPage(url);
    const check = linkCheckPage(url);
    if (calilBookPage(url) || amazon || check) {
      // 確認ページもクエリとフラグメントを落とす。届いたことだけが要る。
      const sent = amazon || check ? new URL(url).origin + new URL(url).pathname : url;
      const target = delivery(sent);
      notice.textContent = 'karita へ送りました。起動確認が出たら確認してください。';
      // 経路をログで区別するため、リンクにだけ via=retry を付ける（決定S 2026-10-13）。
      retry.href = target + '&via=retry';
      retry.hidden = false;
      retry.textContent = '開かない場合は、ここから karita を開く';
      location.href = target;
      return;
    }

    // 予約用の親タブ探索より前に置く。**探索が失敗しても、貸出し・マイページは妨げない。**
    showPurposeLinks(url);

    if (!Number.isInteger(tab.openerTabId)) {
      notice.textContent = '開いた元のタブが見つかりません。現在の URL は手動で送れます。';
      showCurrent(url);
      return;
    }

    grant.addEventListener('click', async () => {
      grant.disabled = true;
      try {
        const allowed = await api.permissions.request({origins: [origin]});
        if (!allowed) {
          notice.textContent = 'カーリルタブの読み取りが許可されませんでした。';
          return;
        }
        grant.hidden = true;
        await inspectParent(tab, url);
      } catch (error) {
        notice.textContent = '権限の確認に失敗しました: ' + String(error);
      } finally {
        grant.disabled = false;
      }
    });
    await inspectParent(tab, url);
  } catch (error) {
    notice.textContent = 'タブの確認に失敗しました: ' + String(error);
  }
})();
