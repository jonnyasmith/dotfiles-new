return {
  "iamcco/markdown-preview.nvim",
  cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
  ft = { "markdown" },
  -- Upstream's installer only downloads a pre-built server binary: it publishes
  -- none for linux-aarch64 (the Pi) and leaves app/ empty whenever the download
  -- fails, with no second attempt. Installing the four runtime deps instead
  -- works on every platform — rpc.vim runs `node app/index.js` when app/bin is
  -- missing, and mise puts node on PATH everywhere.
  build = "cd app && npm install --omit=dev --no-audit --no-fund",
  init = function()
    -- The page is handed to `open` on macOS but to xdg-open on Linux (hence
    -- xdg-utils in mise.toml). Echoing the URL as well is what makes a headless
    -- box, or a machine with no browser association, still usable.
    vim.g.mkdp_echo_preview_url = 1
  end,
}
