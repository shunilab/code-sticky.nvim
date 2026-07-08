# code-sticky.nvim

> 手書きノートの余白メモのように、コードへ付箋を貼る。

コードリーディング中に、コードの行へ付箋（メモ・疑問・指摘）を貼っていくための Neovim プラグイン。付箋はプロジェクト直下 `.code-sticky/notes.md` にプレーンな Markdown として蓄積される。プラグインなしでも読める・AI にそのまま渡せる形式が前提。

Neovim 専用（0.10+）。純 Lua、必須依存ゼロ（Telescope はあれば連携するオプション）。行追跡はしない（行番号固定。コードリーディング用途で、対象コードを編集しない前提）。

## 動作環境

Neovim 0.10 以降。

## ストレージ

プロジェクトルート（`.git` または `.code-sticky` を含むディレクトリ、`vim.fs.root` で判定）直下の `.code-sticky/` に、`notes.md`（現行）と `archive.md`（解決済み）の 2 ファイルのみを持つ。

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
- `->` で始まる行がある → 疑問・指摘への回答（解決済み扱い）

それ以外はメモ。この 3 ルール以上の状態管理はしない。

notes.md 初回作成時、プラグインが冒頭にこの書式を説明するヘッダーを自動で書き込む。AI エージェントに読ませてそのまま回答を追記させる運用を想定している。

プロジェクト外のファイルへのメモは絶対パス（ホーム配下は `~/` 表記）で保存される。

## コマンド

| コマンド | 動作 |
|---|---|
| `:CodeSticky` | カーソル行の付箋をフロートで開く。なければ新規ブランク付箋。既に開いていれば既存フロートへフォーカス |
| `:CodeSticky buffer` | 同上だが、フロートでなく通常ウィンドウ（split）で開く |
| `:CodeSticky list` | `.code-sticky/notes.md` を開く |
| `:CodeSticky archive` | カーソル行の付箋をアーカイブ。複数あれば `vim.ui.select` で選択 |

付箋フロートは本物のバッファ（`buftype=acwrite`）。`:w` で保存、Undo 有効。ノーマルモードの `q` / `<Esc>` で閉じると自動保存される。空白のまま閉じたら何も書き込まれず、既存の付箋を空白にして閉じたら削除される。

## notes.md 内のキーマップ

`.code-sticky/notes.md` を開くと、以下のバッファローカルマップが有効になる（`:CodeSticky list` 経由でも直接 `:e` でも同じ）。

| キー | 動作 |
|---|---|
| `K` | カーソル下エントリが指すコード行の周辺をフロートプレビュー（再度 `K` で閉じる） |
| `<CR>` | 該当ファイル・行へジャンプ（ファイルが短くなっていれば末尾行にクランプ） |
| `ga` | カーソル下エントリをアーカイブ（未保存の編集があれば先に保存してから移す） |

## Sign とジャンプ

付箋のある行に sign が付く。未解決の指摘は `!`、未解決の疑問は `?`、それ以外（メモ・解決済み）は `N`。同一行に複数あれば `!` > `?` > `N` の優先順位で表示する。バッファを開いた時点でスキャンするため、`notes.md` を直接編集した場合はバッファを開き直すと反映される。

`]n` / `[n`（ノーマルモードのみ）でバッファ内の付箋行を前後にジャンプする（count 対応、末尾でラップ）。

## Telescope 連携

[telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) がある場合のみ有効。

```lua
require('telescope').load_extension('code_sticky')
```

| コマンド | 動作 |
|---|---|
| `:Telescope code_sticky` | 全エントリを一覧・プレビュー・`<CR>` でジャンプ |
| `:Telescope code_sticky questions` | 未解決の疑問のみ |
| `:Telescope code_sticky issues` | 未解決の指摘のみ |

## 設定

```lua
require('code-sticky').setup({
  root_markers = { '.code-sticky', '.git' },
  keymaps = {
    jump_next = ']n',
    jump_prev = '[n',
  },
  float = {
    width = 40,
    height = 8,
    border = 'rounded',
    enter_insert = false,
  },
  float_keymaps = {
    close = { 'q', '<Esc>' },
    archive = 'ga',
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

`vim.g.code_sticky_default_mappings = false` で `]n` / `[n` のデフォルトマップを無効化できる。

推奨のリーダーキー割り当て例（デフォルトでは張らない）:

```lua
vim.keymap.set('n', '<leader>nn', '<Cmd>CodeSticky<CR>')
vim.keymap.set('n', '<leader>nl', '<Cmd>CodeSticky list<CR>')
vim.keymap.set('n', '<leader>na', '<Cmd>CodeSticky archive<CR>')
vim.keymap.set('n', '<leader>nb', '<Cmd>CodeSticky buffer<CR>')
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
- `notes.md` 手編集時のライブ再同期（バッファを開き直せば sign は更新される）
- アーカイブからの復元機能
- 本文中に `## パス:行` 形式の行をユーザーが書いた場合にエントリとして誤認識されないような特別扱い（書式契約として、この形式の行は見出しとして扱われる）

詳細は `:h code-sticky`。

## ライセンス

[MIT](LICENSE)
