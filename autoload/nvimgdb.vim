sign define GdbCurrentLine text=⇒
sign define GdbBreakpoint text=●

lua V = require("gdb.v")
lua gdb = require("gdb")


function s:GdbKill()

  " Cleanup commands, autocommands etc
  call nvimgdb#ui#Leave()

  lua gdb.app.cleanup()

  " TabEnter isn't fired automatically when a tab is closed
  call nvimgdb#OnTabEnter()
endfunction


" The checks to be executed when navigating the windows
function! nvimgdb#CheckWindowClosed(...)
  " If this isn't a debugging session, nothing to do
  if !luaeval("gdb.client.checkTab()") | return | endif

  " The tabpage should contain at least two windows, finish debugging
  " otherwise.
  if tabpagewinnr(tabpagenr(), '$') == 1
    call s:GdbKill()
  endif
endfunction

function! nvimgdb#OnTabEnter()
  if !luaeval("gdb.client.checkTab()") | return | endif

  " Restore the signs as they may have been spoiled
  if luaeval("gdb.client.isPaused()")
    lua gdb.cursor.display(1)
  endif

  " Ensure breakpoints are shown if are queried dynamically
  lua gdb.win.queryBreakpoints()
endfunction

function! nvimgdb#OnTabLeave()
  if !luaeval("gdb.client.checkTab()") | return | endif

  " Hide the signs
  lua gdb.cursor.display(0)
  lua gdb.breakpoint.clearSigns()
endfunction


function! nvimgdb#OnBufEnter()
  if !luaeval("gdb.client.checkTab()") | return | endif
  if &buftype ==# 'terminal' | return | endif
  call nvimgdb#keymaps#DispatchSet()
  " Ensure breakpoints are shown if are queried dynamically
  lua gdb.win.queryBreakpoints()
endfunction

function! nvimgdb#OnBufLeave()
  if !luaeval("gdb.client.checkTab()") | return | endif
  if &buftype ==# 'terminal' | return | endif
  call nvimgdb#keymaps#DispatchUnset()
endfunction


function! nvimgdb#Spawn(backend, proxy_cmd, client_cmd)
  call luaeval("gdb.app.init(_A[1], _A[2], _A[3])", [a:backend, a:proxy_cmd, a:client_cmd])

  " Prepare configuration specific to this debugging session
  call nvimgdb#keymaps#Init()

  " Initialize the UI commands, autocommands etc
  call nvimgdb#ui#Enter()

  " Set terminal window keymaps
  call nvimgdb#keymaps#DispatchSetT()

  " Set normal mode keymaps too
  call nvimgdb#keymaps#DispatchSet()

  " Start inset mode in the GDB window
  normal i
endfunction


" Breakpoints need full path to the buffer (at least in lldb)
function! nvimgdb#GetFullBufferPath(buf)
  return expand('#' . a:buf . ':p')
endfunction

function! nvimgdb#ToggleBreak()
  if !luaeval("gdb.client.checkTab()") | return | endif

  if luaeval("gdb.client.isRunning()")
    " pause first
    lua gdb.client.interrupt()
  endif

  let buf = bufnr('%')
  let file_name = nvimgdb#GetFullBufferPath(buf)
  let file_breakpoints = luaeval("gdb.breakpoint.getForFile(_A)", file_name)
  let linenr = line('.')

  if empty(file_breakpoints) || !has_key(file_breakpoints, linenr)
    call luaeval("gdb.client.sendLine(gdb.client.getCommand('breakpoint') .. _A)",
          \ ' ' . file_name . ':' . linenr)
  else
    " There already is a breakpoint on this line: remove
    call luaeval("gdb.client.sendLine(gdb.client.getCommand('delete_breakpoints') .. _A)",
          \ ' ' . file_breakpoints[linenr])
  endif
endfunction


function! nvimgdb#ClearBreak()
  if !luaeval("gdb.client.checkTab()") | return | endif

  lua gdb.breakpoint.cleanupSigns()

  if luaeval("gdb.client.isRunning()")
    " pause first
    lua gdb.client.interrupt()
  endif
  call luaeval("gdb.client.sendLine(gdb.client.getCommand('delete_breakpoints'))")
endfunction


function! nvimgdb#Send(data)
  if !luaeval("gdb.client.checkTab()") | return | endif
  call luaeval("gdb.client.sendLine(gdb.client.getCommand(_A))", a:data)
endfunction


function! nvimgdb#Eval(expr)
  call nvimgdb#Send(printf('print %s', a:expr))
endfunction


function! nvimgdb#Interrupt()
  if !luaeval("gdb.client.checkTab()") | return | endif
  lua gdb.client.interrupt()
endfunction


function! nvimgdb#Kill()
  if !luaeval("gdb.client.checkTab()") | return | endif
  call s:GdbKill()
endfunction

let s:plugin_dir = expand('<sfile>:p:h:h')

function! nvimgdb#GetPluginDir()
  return s:plugin_dir
endfunction

function! nvimgdb#TermOpen(command, tab)
  enew
  return termopen(a:command,
    \ {'tab': a:tab,
    \  'on_stdout': {j,d,e -> luaeval("gdb.client.onStdout(_A[1], _A[2], _A[3])", [j,d,e])}
    \ })
endfunction
