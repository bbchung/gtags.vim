local M = {}

local state = {
  option = '',
  global_command = '',
}

local function is_windows()
  return vim.fn.has('win32') == 1 or vim.fn.has('win16') == 1 or vim.fn.has('win95') == 1
end

local function err(msg)
  vim.api.nvim_echo({ { 'Error: ' .. msg, 'WarningMsg' } }, true, {})
end

local function extract(line, target)
  line = line or ''
  local option = ''
  local c = ''
  local pattern = ''
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
          option = option .. c
          i = i + 1
        end
        if c == 'e' then
          force_pattern = true
        end
      end
    else
      pattern = ''
      while i <= length do
        local ch = line:sub(i, i)
        if ch == "'" then
          pattern = pattern .. vim.g.Gtags_Single_Quote_Char
        elseif ch == '"' then
          pattern = pattern .. vim.g.Gtags_Double_Quote_Char
        else
          pattern = pattern .. ch
        end
        i = i + 1
      end
      if target == 'pattern' then
        return pattern
      end
    end
    while i <= length and line:sub(i, i) == ' ' do
      i = i + 1
    end
  end
  if target == 'option' then
    return option
  end
  return ''
end

local function trim_option(option)
  local result = ''
  local length = #option
  local i = 1
  while i <= length do
    local c = option:sub(i, i)
    if not c:match('[cenpquv]') then
      result = result .. c
    end
    i = i + 1
  end
  return result
end

local function global_command(option)
  local opt = ''
  if option and option ~= '' then
    opt = ' ' .. option
  end
  if vim.g.Gtags_Emacs_Like_Mode == 1 and vim.fn.expand('%') ~= '' then
    local dir = vim.fn.shellescape(vim.fn.expand('%:p:h'))
    return 'cd ' .. dir .. ' && ' .. state.global_command .. opt
  end
  return state.global_command .. opt
end

function M.exec_load(option, long_option, pattern, flags)
  vim.fn.setqflist({}, 'r')
  flags = flags or ''
  local isfile = false
  local opt = ''

  if option:find('f', 1, true) then
    isfile = true
    if vim.fn.filereadable(pattern) == 0 then
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

  local result = vim.fn.system(cmd)
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
  if result == '' then
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

  if vim.g.Gtags_OpenQuickfixWindow == 1 then
    local open = true
    if vim.g.Gtags_Close_When_Single == 1 then
      open = false
      local first = result:find('\n', 1, true)
      if first and result:find('\n', first + 1, true) then
        open = true
      end
    end
    if not open then
      vim.cmd('cclose')
    elseif vim.g.Gtags_VerticalWindow == 1 then
      vim.cmd('topleft vertical copen')
    else
      vim.cmd('botright copen')
    end
  end

  local efm_org = vim.o.errorformat
  vim.o.errorformat = vim.g.Gtags_Efm
  local lines = vim.split(result, '\n', { trimempty = true })
  if flags:find('a', 1, true) then
    vim.fn.setqflist({}, 'a', { lines = lines })
  elseif vim.g.Gtags_No_Auto_Jump == 1 then
    vim.fn.setqflist({}, 'r', { lines = lines })
  else
    vim.fn.setqflist({}, 'r', { lines = lines })
    vim.cmd('cfirst')
  end
  vim.o.errorformat = efm_org
end

function M.run_global(line, flags)
  local pattern = extract(line, 'pattern')
  if pattern == '%' then
    pattern = vim.fn.expand('%')
  elseif pattern == '#' then
    pattern = vim.fn.expand('#')
  end
  local option = extract(line, 'option')
  if pattern == '' then
    state.option = option
    local input_line
    if option:find('f', 1, true) then
      input_line = vim.fn.input('Gtags for file: ', vim.fn.expand('%'), 'file')
    else
      input_line = vim.fn.input(
        'Gtags for pattern: ',
        vim.fn.expand('<cword>'),
        'custom,v:lua.GtagsCandidateCore'
      )
    end
    pattern = extract(input_line, 'pattern')
    if pattern == '' then
      err('Pattern not specified.')
      return
    end
  end
  M.exec_load(option, '', pattern, flags)
end

function M.gtags_cursor()
  local pattern = vim.fn.expand('<cword>')
  local option = string.format('--from-here="%s:%s"', vim.fn.line('.'), vim.fn.expand('%'))
  M.exec_load('', option, pattern, '')
end

function M.gozilla()
  local lineno = vim.fn.line('.')
  local filename = vim.fn.expand('%')
  local cmd
  if vim.g.Gtags_Emacs_Like_Mode == 1 and vim.fn.expand('%') ~= '' then
    local dir = vim.fn.shellescape(vim.fn.expand('%:p:h'))
    cmd = 'cd ' .. dir .. ' && gozilla'
  else
    cmd = 'gozilla'
  end
  vim.fn.system(cmd .. ' +' .. lineno .. ' ' .. filename)
end

function M.auto_update()
  vim.fn.system(global_command() .. ' -u --single-update="' .. vim.fn.expand('%') .. '"')
end

function M.candidate_core(lead, line, pos)
  if state.option == 'g' then
    return ''
  elseif state.option == 'f' then
    local pattern
    if vim.fn.isdirectory(lead) == 1 then
      if lead:match('/$') then
        pattern = lead .. '*'
      else
        pattern = lead .. '/*'
      end
    else
      pattern = lead .. '*'
    end
    return vim.fn.glob(pattern)
  end
  return vim.fn.system(global_command() .. ' ' .. '-c' .. state.option .. ' ' .. lead)
end

function M.command_complete(arg_lead, cmd_line, cursor_pos)
  state.option = extract(cmd_line, 'option')
  local result = M.candidate_core(arg_lead, cmd_line, cursor_pos)
  if result == '' then
    return {}
  end
  return vim.split(result, '\n', { trimempty = true })
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
    local group = vim.api.nvim_create_augroup('GtagsAutoUpdate', { clear = true })
    vim.api.nvim_create_autocmd('BufWritePost', {
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
  vim.api.nvim_create_user_command('Gtags', function(opts)
    M.run_global(opts.args, '')
  end, { nargs = '*', complete = M.command_complete })
  vim.api.nvim_create_user_command('Gtagsa', function(opts)
    M.run_global(opts.args, 'a')
  end, { nargs = '*', complete = M.command_complete })
  vim.api.nvim_create_user_command('GtagsCursor', function()
    M.gtags_cursor()
  end, { nargs = 0 })
  vim.api.nvim_create_user_command('Gozilla', function()
    M.gozilla()
  end, { nargs = 0 })
  vim.api.nvim_create_user_command('GtagsUpdate', function()
    M.auto_update()
  end, { nargs = 0 })
end

function M.setup()
  setup_globals()
  _G.GtagsCandidateCore = function(lead, line, pos)
    return M.candidate_core(lead, line, pos)
  end
  create_commands()
  create_autocmd()
  create_maps()
end

return M
