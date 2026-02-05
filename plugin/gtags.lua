if vim.g.loaded_gtags then
  return
end

require('gtags').setup()

vim.g.loaded_gtags = 1
