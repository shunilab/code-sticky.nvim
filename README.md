# code-sticky.nvim

> 手書きノートの余白メモのように、コードへ付箋を貼る。

コードリーディング中に、コードの行へ付箋（メモ・疑問・指摘）を貼っていくための Neovim プラグイン。付箋はプロジェクト直下 `.code-sticky/notes.md` にプレーンな Markdown として蓄積される。プラグインなしでも読める・AI にそのまま渡せる形式が前提。

Neovim 専用（0.10+）。純 Lua、必須依存ゼロ（Telescope はあれば連携するオプション）。行追跡はしない（行番号固定。コードリーディング用途で、対象コードを編集しない前提）。

## 動作環境

Neovim 0.10 以降。

## ストレージ

プロジェクトルート（`.git` または `.code-sticky` を含むディレクトリ、`vim.fs.root` で判定）直下の `.code-sticky/` に、`notes.md`（現行）と `archive.md`（アーカイブ済み）の 2 ファイルのみを持つ。

```markdown
## lua/foo.lua:42
? この分岐は何のため？

## lua/foo.lua:42
! ここでハンドルがリークしている
-> 123abc で修正済み
```

本文の慣習（プラグインが軽くパースする）:

- 最初の空でない行が `?` で始まる → 疑問
- 最初の空でない行が `!` で始まる → 指摘（コードレビュー用途）
- `->` で始まる行がある → 疑問・指摘への回答（回答済み扱い）

それ以外はメモ。この 3 ルール以上の状態管理はしない。回答済みは「解決した」とは限らないため、内容を確認して解決とみなせたら `ga` でアーカイブする運用を想定している。

notes.md 初回作成時、プラグインが冒頭にこの書式を説明するヘッダーを自動で書き込む。AI エージェントに読ませてそのまま回答を追記させる運用を想定している。

プロジェクト外のファイルへのメモは絶対パス（ホーム配下は `~/` 表記）で保存される。

`notes.md` を Neovim 内で手編集して未保存のまま（`ga` や `:CodeStickyNew` など）他の操作でプラグインが notes.md を書き換える場合、その未保存編集をベースに書き込む（ディスク側は無視される）。バッファが未保存でなければディスクが正となる（AI エージェントが Neovim の外から notes.md を直接編集する運用を想定）。

## コマンド

| コマンド | 動作 |
|---|---|
| `:CodeSticky` | カーソル行の付箋をフロートで開く。なければ新規ブランク付箋。複数あれば全エントリを横に並べて開き、フォーカスは先頭へ。既に開いていれば既存フロートへフォーカス |
| `:CodeSticky buffer` | 同上だが、フロートでなく通常ウィンドウ（split）で開く |
| `:CodeSticky list` | `.code-sticky/notes.md` を開く |
| `:CodeSticky list archive` | `.code-sticky/archive.md` を開く（閲覧用。`K`/`<CR>` のみ、`ga` は張らない） |
| `:CodeSticky archive` | カーソル行の付箋をアーカイブ。複数あれば `vim.ui.select` で選択 |
| `:CodeSticky undo` | notes.md への直近の変更（保存・削除・アーカイブ）を1つ取り消す。繰り返すとさらに遡れる |
| `:CodeSticky redo` | `:CodeSticky undo` で取り消した変更をやり直す |
| `:CodeSticky sort` | notes.md のエントリを (path, 行番号) で安定ソートして書き戻す。`:CodeSticky undo` で戻せる |
| `:CodeSticky sweep` | 回答済み（`answered`）エントリを一括で `archive.md` へ移動する。確認ダイアログあり。0件なら通知のみ |
| `:CodeSticky qf [questions\|issues\|memos\|answered]` | 該当エントリを quickfix リストへ積んで開く（`]q`/`[q` で巡回）。引数省略は全エントリ |
| `:CodeSticky jumpfloat [on\|off\|toggle]` | `jump_opens_float` を実行時に切り替える（`setup()` の再実行不要）。引数省略は `toggle` と同じ |
| `:CodeStickyNew` | 付箋フロート/ウィンドウ内で実行。同じ行に新規ブランク付箋を隣に追加しフォーカス移動（デフォルトマップ `<C-n>`） |

付箋フロートは本物のバッファ（`buftype=acwrite`）。`:w` で保存、Undo 有効。ノーマルモードの `q` / `<Esc>` で閉じると自動保存される。空白のまま閉じたら何も書き込まれず、既存の付箋を空白にして閉じたら削除される。

同じ行に複数の付箋が開いているとき、フロート内で以下のバッファローカルマップが有効になる。

| キー | 動作 |
|---|---|
| `<Tab>` / `<S-Tab>` | 同じ行の付箋間でフォーカスを巡回 |
| `<C-n>` | `:CodeStickyNew` と同じ。隣に新規ブランク付箋を追加してフォーカス移動 |
| `ga` | フロート内の付箋をアーカイブ（未保存の編集は先に保存してから移す） |

`:CodeSticky undo` は notes.md 専用の hidden バッファを介して書き込みを行い、その Undo 履歴をそのまま利用している。`vim.o.undofile = true`（このプラグイン自体は変更しない、ユーザーの既存設定に従う）であれば Neovim を再起動しても取り消せる。アーカイブ先の archive.md 側は対象外（複製が残る）。

## notes.md 内のキーマップ

`.code-sticky/notes.md` を開くと、以下のバッファローカルマップが有効になる（`:CodeSticky list` 経由でも直接 `:e` でも同じ）。

| キー | 動作 |
|---|---|
| `K` | カーソル下エントリが指すコード行の周辺をフロートプレビュー（再度 `K` で閉じる） |
| `<CR>` | 該当ファイル・行へジャンプ（ファイルが短くなっていれば末尾行にクランプ） |
| `ga` | カーソル下エントリをアーカイブ（未保存の編集があれば先に保存してから移す） |

## Sign とジャンプ

付箋のある行に sign が付く。未回答の指摘は `!`、未回答の疑問は `?`、それ以外（メモ・回答済み）は `N`。同一行に複数あれば `!` > `?` > `N` の優先順位で表示する。バッファを開いた時点でスキャンするため反映される。`notes.md` を直接編集して保存した場合も、影響を受けるコードバッファの sign と開いている付箋の index が自動で追従する。

`]n` / `[n`（ノーマルモードのみ）でバッファ内の付箋行を前後にジャンプする（count 対応、末尾でラップ）。

## Telescope 連携

[telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) がある場合のみ有効。

```lua
require('telescope').load_extension('code_sticky')
```

| コマンド | 動作 |
|---|---|
| `:Telescope code_sticky` | 全エントリを一覧・プレビュー・`<CR>` でジャンプ |
| `:Telescope code_sticky questions` | 未回答の疑問のみ |
| `:Telescope code_sticky issues` | 未回答の指摘のみ |
| `:Telescope code_sticky memos` | メモのみ |
| `:Telescope code_sticky answered` | 回答済みのみ |

## 設定

```lua
require('code-sticky').setup({
  root_markers = { '.code-sticky', '.git' },
  keymaps = {
    jump_next = ']n',
    jump_prev = '[n',
  },
  jump_opens_float = false, -- ]n / [n でジャンプ後にそのままフロートで開く（:CodeSticky jumpfloat で実行時にも切替可）
  float = {
    width = 40,
    height = 8,
    gap = 2, -- 複数の付箋を横に並べるときの間隔
    border = 'rounded',
    enter_insert = false,
  },
  float_keymaps = {
    close = { 'q', '<Esc>' },
    archive = 'ga',
    new_sibling = '<C-n>',
    focus_next = '<Tab>',
    focus_prev = '<S-Tab>',
  },
  notes_keymaps = {
    preview = 'K',
    jump = '<CR>',
    archive = 'ga',
  },
  preview = {
    context = 8, -- K プレビューで前後何行を表示するか
  },
  signs = {
    memo = { text = 'N', hl = 'DiagnosticSignInfo' },
    question = { text = '?', hl = 'DiagnosticSignWarn' },
    issue = { text = '!', hl = 'DiagnosticSignError' },
  },
})
```

`vim.g.code_sticky_default_mappings = false` で `]n` / `[n` のデフォルトマップを無効化できる。`keymaps` は `setup()` 経由で登録されるため、lazy.nvim の `opts`/`config` で指定した値が正しく反映される。

キーマップの衝突に注意: `]n` / `[n` は [vim-unimpaired](https://github.com/tpope/vim-unimpaired) の conflict marker ジャンプと衝突する。`ga` は組み込みの `:ascii` 相当や一部の align 系プラグインの慣習と衝突し得るが、いずれも当プラグインのバッファローカルマップがそれを上書きする形になる。

推奨のリーダーキー割り当て例（デフォルトでは張らない）:

```lua
vim.keymap.set('n', '<leader>ss', '<Cmd>CodeSticky<CR>')
vim.keymap.set('n', '<leader>sl', '<Cmd>CodeSticky list<CR>')
vim.keymap.set('n', '<leader>sa', '<Cmd>CodeSticky archive<CR>')
vim.keymap.set('n', '<leader>sb', '<Cmd>CodeSticky buffer<CR>')
```

## インストール

Neovim（vim.pack / 0.12+）:

```lua
vim.pack.add({ 'https://github.com/shunilab/code-sticky.nvim' })
```

Neovim（lazy.nvim）:

```lua
{ 'shunilab/code-sticky.nvim', opts = {} }
```

プラグインマネージャー無し（Neovim 標準の packages 機構）:

```sh
git clone https://github.com/shunilab/code-sticky.nvim \
  ~/.local/share/nvim/site/pack/plugins/start/code-sticky.nvim
```

いずれの方法でも `require('code-sticky').setup()` の呼び出しが必要（`opts = {}` でも可）。

## 明示的にやらないこと

- 複数 Neovim インスタンスの同時書き込みやクラッシュ時のアトミック性
- コード編集時の行追従（行番号は固定。対象コードを編集しない前提）
- アーカイブからの復元機能
- 本文中に `## パス:行` 形式の行をユーザーが書いた場合にエントリとして誤認識されないような特別扱い（書式契約として、この形式の行は見出しとして扱われる）

詳細は `:h code-sticky`。

## ライセンス

[MIT](LICENSE)
