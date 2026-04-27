local M = {}

local api = vim.api
local fn = vim.fn

local state = {
  did_setup = false,
  option = '',
  global_command = '',
}

local function is_windows()
  return fn.has('win32') == 1 or fn.has('win16') == 1 or fn.has('win95') == 1
end

local function err(msg)
  api.nvim_echo({ { 'Error: ' .. msg, 'WarningMsg' } }, true, {})
end

local function parse_command_line(line)
  line = line or ''
  local option = {}
  local c = ''
  local pattern
  local force_pattern = false
  local length = #line
  local i = 1

  if line:sub(1, 5) == 'Gtags' then
    i = 6
  end
  while i <= length and line:sub(i, i) == ' ' do
    i = i + 1
  end
  while i <= length do
    if line:sub(i, i) == '-' and not force_pattern then
      i = i + 1
      if i <= length and line:sub(i, i) == '-' then
        while i <= length and line:sub(i, i) ~= ' ' do
          i = i + 1
        end
      else
        while i <= length and line:sub(i, i) ~= ' ' do
          c = line:sub(i, i)
          option[#option + 1] = c
          i = i + 1
        end
        if c == 'e' then
          force_pattern = true
        end
      end
    else
      local pattern_parts = {}
      while i <= length do
        local ch = line:sub(i, i)
        if ch == "'" then
          pattern_parts[#pattern_parts + 1] = vim.g.Gtags_Single_Quote_Char
        elseif ch == '"' then
          pattern_parts[#pattern_parts + 1] = vim.g.Gtags_Double_Quote_Char
        else
          pattern_parts[#pattern_parts + 1] = ch
        end
        i = i + 1
      end
      pattern = table.concat(pattern_parts)
      break
    end
    while i <= length and line:sub(i, i) == ' ' do
      i = i + 1
    end
  end
  return table.concat(option), pattern or ''
end

local function trim_option(option)
  return option:gsub('[cenpquv]', '')
end

local function global_command(option)
  local opt = ''
  if option and option ~= '' then
    opt = ' ' .. option
  end
  local current_file = fn.expand('%')
  if vim.g.Gtags_Emacs_Like_Mode == 1 and current_file ~= '' then
    local dir = fn.shellescape(fn.expand('%:p:h'))
    return 'cd ' .. dir .. ' && ' .. state.global_command .. opt
  end
  return state.global_command .. opt
end

local function file_candidates(lead)
  local pattern
  if fn.isdirectory(lead) == 1 then
    if lead:match('/$') then
      pattern = lead .. '*'
    else
      pattern = lead .. '/*'
    end
  else
    pattern = lead .. '*'
  end
  return fn.glob(pattern, false, true)
end

local function global_complete(lead)
  return global_command() .. ' -c' .. state.option .. ' ' .. fn.shellescape(lead)
end

function M.exec_load(option, long_option, pattern, flags)
  fn.setqflist({}, 'r')
  flags = flags or ''
  local isfile = false
  local opt = ''

  if option:find('f', 1, true) then
    isfile = true
    if fn.filereadable(pattern) == 0 then
      err('File ' .. pattern .. ' not found.')
      return
    end
  end
  if long_option ~= '' then
    opt = long_option .. ' '
  end
  opt = opt .. '--result=' .. vim.g.Gtags_Result .. ' -q' .. trim_option(option)
  local cmd
  local quote = vim.g.Gtags_Shell_Quote_Char
  if isfile then
    cmd = global_command('--path-style=absolute') .. ' ' .. opt .. ' ' .. quote .. pattern .. quote
  else
    cmd = global_command('--path-style=absolute') .. ' ' .. opt .. 'e ' .. quote .. pattern .. quote
  end

  local lines = fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then
    if vim.v.shell_error == 2 then
      err('invalid arguments. please use the latest GLOBAL.')
    elseif vim.v.shell_error == 3 then
      err('GTAGS not found.')
    else
      err('global command failed. command line: ' .. cmd)
    end
    return
  end
  if #lines == 0 then
    if opt:find('f', 1, true) then
      err('Tag not found in ' .. pattern .. '.')
    elseif opt:find('P', 1, true) then
      err('Path which matches to ' .. pattern .. ' not found.')
    elseif opt:find('g', 1, true) then
      err('Line which matches to ' .. pattern .. ' not found.')
    else
      err('Tag which matches to ' .. quote .. pattern .. quote .. ' not found.')
    end
    return
  end

  local efm_org = vim.o.errorformat
  vim.o.errorformat = vim.g.Gtags_Efm
  if flags:find('a', 1, true) then
    fn.setqflist({}, 'a', { lines = lines })
  else
    fn.setqflist({}, 'r', { lines = lines })
  end
  vim.o.errorformat = efm_org

  if vim.g.Gtags_OpenQuickfixWindow == 1 then
    local open = true
    if vim.g.Gtags_Close_When_Single == 1 then
      open = #lines > 1
    end
    if not open then
      vim.cmd('cclose')
    elseif vim.g.Gtags_VerticalWindow == 1 then
      vim.cmd('topleft vertical copen')
    else
      vim.cmd('botright copen')
    end
  end

  if not flags:find('a', 1, true) and vim.g.Gtags_No_Auto_Jump ~= 1 then
    vim.cmd('cfirst')
  end
end

function M.run_global(line, flags)
  local option, pattern = parse_command_line(line)
  if pattern == '%' then
    pattern = fn.expand('%')
  elseif pattern == '#' then
    pattern = fn.expand('#')
  end
  if pattern == '' then
    state.option = option
    local input_line
    if option:find('f', 1, true) then
      input_line = fn.input('Gtags for file: ', fn.expand('%'), 'file')
    else
      input_line = fn.input(
        'Gtags for pattern: ',
        fn.expand('<cword>'),
        'custom,v:lua.GtagsCandidateCore'
      )
    end
    local _, input_pattern = parse_command_line(input_line)
    pattern = input_pattern
    if pattern == '' then
      err('Pattern not specified.')
      return
    end
  end
  M.exec_load(option, '', pattern, flags)
end

function M.gtags_cursor()
  local pattern = fn.expand('<cword>')
  local option = string.format('--from-here="%s:%s"', fn.line('.'), fn.expand('%'))
  M.exec_load('', option, pattern, '')
end

function M.gozilla()
  local lineno = fn.line('.')
  local filename = fn.expand('%')
  local cmd
  if vim.g.Gtags_Emacs_Like_Mode == 1 and filename ~= '' then
    local dir = fn.shellescape(fn.expand('%:p:h'))
    cmd = 'cd ' .. dir .. ' && gozilla'
  else
    cmd = 'gozilla'
  end
  fn.system(cmd .. ' +' .. lineno .. ' ' .. fn.shellescape(filename))
end

function M.auto_update()
  fn.system(global_command() .. ' -u --single-update=' .. fn.shellescape(fn.expand('%')))
end

function M.candidate_core(lead, line, pos)
  if state.option == 'g' then
    return ''
  elseif state.option == 'f' then
    return table.concat(file_candidates(lead), '\n')
  end
  return fn.system(global_complete(lead))
end

function M.command_complete(arg_lead, cmd_line, cursor_pos)
  state.option = parse_command_line(cmd_line)
  if state.option == 'g' then
    return {}
  elseif state.option == 'f' then
    return file_candidates(arg_lead)
  end
  return fn.systemlist(global_complete(arg_lead))
end

local function setup_globals()
  if vim.g.Gtags_OpenQuickfixWindow == nil then
    vim.g.Gtags_OpenQuickfixWindow = 1
  end
  if vim.g.Gtags_VerticalWindow == nil then
    vim.g.Gtags_VerticalWindow = 0
  end
  if vim.g.Gtags_Auto_Map == nil then
    vim.g.Gtags_Auto_Map = 0
  end
  if vim.g.Gtags_Auto_Update == nil then
    vim.g.Gtags_Auto_Update = 0
  end
  if vim.g.Gtags_Emacs_Like_Mode == nil then
    vim.g.Gtags_Emacs_Like_Mode = 0
  end
  if vim.g.Gtags_No_Auto_Jump == nil then
    if vim.g.Dont_Jump_Automatically == nil then
      vim.g.Gtags_No_Auto_Jump = 0
    else
      vim.g.Gtags_No_Auto_Jump = vim.g.Dont_Jump_Automatically
    end
  end
  if vim.g.Gtags_Close_When_Single == nil then
    vim.g.Gtags_Close_When_Single = 0
  end

  if vim.g.Gtags_Use_Tags_Format ~= nil then
    vim.g.Gtags_Result = 'ctags'
    vim.g.Gtags_Efm = '%m\t%f\t%l'
  end
  if vim.g.Gtags_Result == nil then
    vim.g.Gtags_Result = 'ctags-mod'
  end
  if vim.g.Gtags_Efm == nil then
    vim.g.Gtags_Efm = '%f\t%l\t%m'
  end

  if vim.g.Gtags_Shell_Quote_Char == nil then
    if is_windows() then
      vim.g.Gtags_Shell_Quote_Char = '"'
    else
      vim.g.Gtags_Shell_Quote_Char = "'"
    end
  end
  if vim.g.Gtags_Single_Quote_Char == nil then
    if is_windows() then
      vim.g.Gtags_Single_Quote_Char = "'"
      vim.g.Gtags_Double_Quote_Char = '\\"'
    else
      local sq = "'"
      local dq = '"'
      vim.g.Gtags_Single_Quote_Char = sq .. dq .. sq .. dq .. sq
      vim.g.Gtags_Double_Quote_Char = '"'
    end
  end

  state.global_command = vim.env.GTAGSGLOBAL
  if not state.global_command or state.global_command == '' then
    state.global_command = 'global'
  end
end

local function create_autocmd()
  if vim.g.Gtags_Auto_Update == 1 then
    local group = api.nvim_create_augroup('GtagsAutoUpdate', { clear = true })
    api.nvim_create_autocmd('BufWritePost', {
      group = group,
      pattern = '*',
      callback = function()
        M.auto_update()
      end,
    })
  end
end

local function create_maps()
  if vim.g.Gtags_Auto_Map == 1 then
    local opts = { remap = true }
    vim.keymap.set('n', '<F2>', ':copen<CR>', opts)
    vim.keymap.set('n', '<F4>', ':cclose<CR>', opts)
    vim.keymap.set('n', '<F5>', ':Gtags ', opts)
    vim.keymap.set('n', '<F6>', ':Gtags -f %<CR>', opts)
    vim.keymap.set('n', '<F7>', ':GtagsCursor<CR>', opts)
    vim.keymap.set('n', '<F8>', ':Gozilla<CR>', opts)
    vim.keymap.set('n', '<C-n>', ':cn<CR>', opts)
    vim.keymap.set('n', '<C-p>', ':cp<CR>', opts)
    vim.keymap.set('n', '<C-\\><C-]>', ':GtagsCursor<CR>', opts)
  end
end

local function create_commands()
  api.nvim_create_user_command('Gtags', function(opts)
    M.run_global(opts.args, '')
  end, { nargs = '*', complete = M.command_complete, force = true })
  api.nvim_create_user_command('Gtagsa', function(opts)
    M.run_global(opts.args, 'a')
  end, { nargs = '*', complete = M.command_complete, force = true })
  api.nvim_create_user_command('GtagsCursor', function()
    M.gtags_cursor()
  end, { nargs = 0, force = true })
  api.nvim_create_user_command('Gozilla', function()
    M.gozilla()
  end, { nargs = 0, force = true })
  api.nvim_create_user_command('GtagsUpdate', function()
    M.auto_update()
  end, { nargs = 0, force = true })
end

function M.setup()
  if state.did_setup then
    return
  end
  setup_globals()
  _G.GtagsCandidateCore = function(lead, line, pos)
    return M.candidate_core(lead, line, pos)
  end
  create_commands()
  create_autocmd()
  create_maps()
  vim.g.loaded_gtags = 1
  state.did_setup = true
end

return M
