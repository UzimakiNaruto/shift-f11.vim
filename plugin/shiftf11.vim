
if exists('g:shiftf11_loaded')
  finish
endif
let g:shiftf11_loaded = 1

" map<fullpath, map<line, {'text': line_text}>>
let s:sign_name = 'shiftf11_bookmarks'
let s:need_flush = 1

let g:shiftf11_bookmarks = {}
let g:shiftf11_sign_group = s:sign_name
let g:shiftf11_sign_text = '√'
let g:shiftf11_cache_path = '~/.shiftf11.cache'


let s:signs = sign_getdefined(s:sign_name)
if !empty(s:signs) 
  echom 'sign group ' . s:sign_name . ' already defined'
  finish
endif
unlet s:signs

augroup shiftf11
  au!
  autocmd BufWinEnter * call s:redraw_bookmark()
  au BufWritePost * call s:update_when_save(bufname())
  au VimEnter * call s:read_checkpoint()
augroup end
nnoremap <silent> <F11> :call <SID>place_sign(bufname(), line('.'), v:true)<cr>
nnoremap <silent> <F12> :call ShiftF11_fzf_view()<cr> 

function! s:define_sign(sign_name) 
  call sign_define(s:sign_name, {
        \ 'text': g:shiftf11_sign_text
        \ })
endfunction
call s:define_sign(s:sign_name)

function! s:place_sign(buf, lnum, remove_exist) abort
  if empty(a:buf)
    echo 'Not support bookmark on unsaved buffer'
    return
  endif
  let fullpath = fnamemodify(a:buf, ':p')
  let id = s:get_line_sign_id(a:buf, a:lnum)
  if id
    if !a:remove_exist | return | endif

    " remove exist one
    call sign_unplace(g:shiftf11_sign_group, {'buffer': a:buf, 'id': id})
    call s:add_or_remove(0, fullpath, a:lnum, '')
  else
    " add one
    call sign_place(0, g:shiftf11_sign_group, s:sign_name, a:buf, {'lnum':a:lnum, 'priority': 11})
    call s:add_or_remove(1, fullpath, a:lnum, getline('.'))
  endif
endfunction

function! s:get_line_sign_id(buf, lnum) abort
  let signed = sign_getplaced(a:buf, {
    \ 'group': g:shiftf11_sign_group,
    \ 'lnum': a:lnum,
    \ })
  if exists('signed[0].signs[0].id')
    return signed[0].signs[0].id
  endif
endfunction

function s:add_or_remove(isadd, buf_fullpath, lnum, line_text) abort
  let dict = g:shiftf11_bookmarks
  let buf_marks = get(dict, a:buf_fullpath, {})
  if a:isadd
    let buf_marks[a:lnum] = {'text': a:line_text}
  else
    if has_key(buf_marks, a:lnum)
      call remove(buf_marks, a:lnum)
    endif
  endif

  if !empty(buf_marks)
    let dict[a:buf_fullpath] = buf_marks
  elseif has_key(dict, a:buf_fullpath)
    call remove(dict, a:buf_fullpath)
  endif
  call s:save_checkpoint()
endfunction

function s:save_checkpoint()
  if !s:need_flush
    return
  endif

  let data = json_encode(g:shiftf11_bookmarks)
  let writepath = expand(g:shiftf11_cache_path)
  if !filereadable(writepath)
    call system('touch ' . writepath)
  endif
  call writefile([data], writepath)
endfunction

function s:read_checkpoint()
  let path = expand(g:shiftf11_cache_path)
  if filereadable(path)
    let data = readfile(path)
    if exists('data[0]')
      let g:shiftf11_bookmarks = json_decode(data[0])
    endif
  endif
endfunction

function s:redraw_bookmark()
  let buf_fp = s:cur_buf_fullpath()
  let lines = get(g:shiftf11_bookmarks, buf_fp, v:null)
  if empty(lines)
    return
  endif

  let t = s:need_flush
  let s:need_flush = 0
  try
    let buf = bufname()
    for lnum in keys(lines)
      call s:place_sign(buf, lnum, v:false)
    endfor
  finally
    let s:need_flush = t
  endtry
endfunction

function s:cur_buf_fullpath() 
  return expand('%:p')
endfunction

function s:shiftf11_clean() abort
  let invalid_files = []
  let dict = g:shiftf11_bookmarks
  for fp in keys(dict)
    if !filereadable(expand(fp))
      call add(invalid_files, fp)
    endif
  endfor

  if !empty(invalid_files)
    for f in invalid_files
      if has_key(dict, f)
        call remove(dict, f)
      endif
    endfor

    call s:save_checkpoint()
  endif
endfunction

function s:update_when_save(buf)
  let signed = sign_getplaced(a:buf, {'group': g:shiftf11_sign_group})
  if !exists("signed[0].signs[0]")
    return
  endif
  let signed = signed[0].signs
  let fullpath = fnamemodify(a:buf, ':p')
  if has_key(g:shiftf11_bookmarks, fullpath)
    call remove(g:shiftf11_bookmarks, fullpath)
  endif
  let t = s:need_flush
  try
    let s:need_flush = 0
    for sign in signed
      call s:add_or_remove(1, fullpath, sign.lnum, getbufline(a:buf, sign.lnum))
    endfor
  finally
    let s:need_flush = t
  endtry

  call s:save_checkpoint()
endfunction

command -bang -nargs=0 CleanShiftF11 call s:shiftf11_clean()

" =============================================================================
" view bookmarks
" =============================================================================
function s:handle_view(lines)
  if empty(a:lines)
    return
  endif

  let qfl = []
  for line in a:lines
    let [lnum, fp; text] = split(line, '[: ]')
    call add(qfl, {'filename': fp, 'lnum': lnum, 'text': join(text, '')})
  endfor
  call setqflist(qfl)

  if len(a:lines) > 1
    copen
  endif
  cfirst
  wincmd p

  " let data = a:lines[0]
  " let [lnum, fp] = split(data) 
  " let bnr = bufnr(fp)
  " if bnr < 0
  "   silent exe 'e '.fp
  "   return
  " else
  "   exe 'buffer'.bnr
  " endif
  " exe lnum
endfunction

function ShiftF11_fzf_view()
  let signs = []
  for [filepath, lines] in items(g:shiftf11_bookmarks)
    for [lnum, attrs] in items(lines)
      call add(signs, printf('%8s:%s %s', lnum, filepath, attrs.text))
    endfor
  endfor

  return fzf#run(fzf#wrap("shift11_signs", {
    \ 'source': signs,
    \ 'sink*': function('s:handle_view'),
    \ 'options': '-m --prompt "ShiftF11 Signs> "'
    \ }))
endfunction

" =============================================================================
" remove bookmarks
" =============================================================================
function s:handle_remove(lines)
  if empty(a:lines)
    return
  endif
  
  let t = s:need_flush
  let s:need_flush = 0
  try
    for line in a:lines
      let [lnum, fp; text] = split(line, '[: ]')
      let buf = bufname(fp)
      if !empty(buf)
        call s:place_sign(buf, lnum, 1)
      endif

      let bufmarks = get(g:shiftf11_bookmarks, fp, {})
      if has_key(bufmarks, lnum)
        call remove(bufmarks, lnum)
      endif
      if empty(bufmarks) && has_key(g:shiftf11_bookmarks, fp)
        call remove(g:shiftf11_bookmarks, fp)
      endif
    endfor
  finally
    let s:need_flush = t
  endtry

  call s:save_checkpoint()
endfunction

function ShiftF11_fzf_remove()
  let signs = []
  for [filepath, lines] in items(g:shiftf11_bookmarks)
    for [lnum, attrs] in items(lines)
      call add(signs, printf('%8s:%s %s', lnum, filepath, attrs.text))
    endfor
  endfor
  
  return fzf#run(fzf#wrap("shift11_signs", {
    \ 'source': signs,
    \ 'sink*': function('s:handle_remove'),
    \ 'options': '-m --prompt "ShiftF11 Remove> "'
    \ }))
endfunction
