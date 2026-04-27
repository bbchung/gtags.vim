if vim.g.loaded_gtags then
  return
end

vim.g.loaded_gtags = 1

local api = vim.api

local function gtags()
  local mod = require('gtags')
  mod.setup()
  return mod
end

api.nvim_create_user_command('Gtags', function(opts)
  gtags().run_global(opts.args, '')
end, {
  nargs = '*',
  complete = function(arg_lead, cmd_line, cursor_pos)
    return gtags().command_complete(arg_lead, cmd_line, cursor_pos)
  end,
})

api.nvim_create_user_command('Gtagsa', function(opts)
  gtags().run_global(opts.args, 'a')
end, {
  nargs = '*',
  complete = function(arg_lead, cmd_line, cursor_pos)
    return gtags().command_complete(arg_lead, cmd_line, cursor_pos)
  end,
})

api.nvim_create_user_command('GtagsCursor', function()
  gtags().gtags_cursor()
end, { nargs = 0 })

api.nvim_create_user_command('Gozilla', function()
  gtags().gozilla()
end, { nargs = 0 })

api.nvim_create_user_command('GtagsUpdate', function()
  gtags().auto_update()
end, { nargs = 0 })

if vim.g.Gtags_Auto_Map == 1 or vim.g.Gtags_Auto_Update == 1 then
  gtags().setup()
end
