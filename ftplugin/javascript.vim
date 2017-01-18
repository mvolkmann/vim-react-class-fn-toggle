"let p = expand('<sfile>:h') . '/foo.vim'
"echo 'p = ' . p
"execute '0source ' + p

" This file depends on many functions defined in plugins/utilities.vim.

function! JSXCommentAdd()
  " Get first and last line number selected in visual mode.
  let firstLineNum = line("'<")
  let lastLineNum = line("'>")

  let column = match(getline(firstLineNum), '\w')
  let indent = repeat(' ', column - 1)

  call append(lastLineNum, indent . '*/}')
  call append(firstLineNum - 1, indent . '{/*')
endf

function! JSXCommentRemove()
  let lineNum = line('.')
  let startLineNum = FindPreviousLine(lineNum, '{/\*')
  if startLineNum == 0
    echo 'no JSX comment found'
    return
  endif

  let endLineNum = FindNextLine(lineNum, '*/}')
  call DeleteLine(endLineNum)
  call DeleteLine(startLineNum)
endf

" Converts a React component definition from a class to an arrow function.
function! ReactClassToFn()
  let line = getline('.') " gets entire current line
  let tokens = split(line, ' ')
  if tokens[0] !=# 'class'
    echo 'must start with "class"'
    return
  endif
  if line !~# ' extends Component {$' &&
  \ line !~# ' extends React.Component {$'
    echo 'must extend Component'
    return
  endif

  let startLineNum = line('.')
  let endLineNum = FindNextLine(startLineNum, '^}')
  if !endLineNum
    echo 'end of class definition not found'
    return
  endif

  let className = tokens[1]

  let displayNameLineNum = FindNextLine(startLineNum, 'static displayName = ')
  if displayNameLineNum
    let line = getline(displayNameLineNum)
    let pattern = '\vstatic displayName \= ''(.+)'';'
    let result = matchlist(line, pattern)
    let displayName = result[1] " first capture group
  endif

  let propTypesLineNum = FindNextLine(startLineNum, 'static propTypes = {$')
  let propTypesInsideClass = propTypesLineNum ? 1 : 0
  if !propTypesLineNum
    let propTypesLineNum = FindNextLine(startLineNum, className . '.propTypes = {$')
  endif
  if propTypesLineNum
    let propTypesLines = GetLinesTo(propTypesLineNum + 1, '};$')
    call PopList(propTypesLines)
    let propNames = []
    for line in propTypesLines
      call add(propNames, split(Trim(line), ':')[0])
    endfor
    let params = '{' . join(propNames, ', ') . '}'
  else
    let params = ''
  endif

  let renderLineNum = FindNextLine(startLineNum, ' render() {')
  if renderLineNum
    let renderLines = GetLinesTo(renderLineNum + 1, '^\s*}$')

    " Remove last line that closes the render method.
    call PopList(renderLines)

    " Remove any lines that destructure this.props since
    " all are destructured in the arrow function parameter list.
    let length = len(renderLines)
    let index = 0
    while index < length
      let line = renderLines[index]
      if line =~# '} = this.props;'
        call remove(renderLines, index)
        let length -= 1
      endif
      let index += 1
    endw

    " If the first render line is empty, remove it.
    if len(Trim(renderLines[0])) == 0
      call remove(renderLines, 0)
    endif
  else
    let renderLines = []
  endif

  let lines = ['const ' . className . ' = (' . params . ') => {']

  for line in renderLines
    call add(lines, line[2:])
  endfor
  call add(lines, '};')

  if exists('displayName')
    let lines += [
    \ '',
    \ className . ".displayName = '" . displayName . "';"
  \ ]
  endif

  if exists('propTypesLines') && propTypesInsideClass
    let lines += ['', className . '.propTypes = {']
    for line in propTypesLines
      call add(lines, '  ' . Trim(line))
    endfor
    let lines += ['};']
  endif

  call DeleteLines(startLineNum, endLineNum)
  call append(startLineNum - 1, lines)
endf

" Converts a React component definition from an arrow function to a class.
function! ReactFnToClass()
  let line = getline('.') " gets entire current line

  if line !~# ' =>'
    echo 'not an arrow function'
    return
  endif

  let tokens = split(line, ' ')

  if (tokens[0] !=# 'const')
    echo 'arrow function should be assigned using "const"'
    return
  endif

  if (tokens[2] !=# '=')
    echo 'arrow function should be assigned to variable'
    return
  endif

  let tokenCount = len(tokens)
  let lastToken = tokens[tokenCount - 1]
  let prevToken = tokens[tokenCount - 2]
  let isAF = lastToken ==# '=>' ||
  \ (prevToken ==# '=>' && lastToken ==# '{')
  if (!isAF)
    echo 'arrow function first line must end with => or => {'
    return
  endif

  let className = tokens[1]

  let lineNum = line('.')

  let hasBlock = line =~# '{$'
  if hasBlock
    " Find next line that only contains "};".
    if !FindNextLine(lineNum, '^\w*};\w*$')
      echo 'arrow function end not found'
      return
    endif
  else
    " Find next line that ends with ";".
    if !FindNextLine(lineNum, ';\w*$')
      echo 'arrow function end not found'
      return
    endif
  endif

  let renderLines = GetLinesTo(lineNum + 1, '^};$')
  call PopList(renderLines)

  call DeleteLines(lineNum,
  \ lineNum + len(renderLines) + (hasBlock ? 1 : 0))

  if !hasBlock
    " Remove semicolon from end of last line if exists.
    let index = len(renderLines) - 1
    let lastRenderLine = renderLines[index]
    if lastRenderLine =~# ';$'
      let renderLines[index] = lastRenderLine[0:-2]
    endif
  endif

  let displayNameLineNum = FindNextLine(lineNum, className . '.displayName =')
  if displayNameLineNum
    let displayName = LastToken(getline(displayNameLineNum))
    call DeleteLine(displayNameLineNum)
    call DeleteLineIfBlank(displayNameLineNum - 1)
  endif

  let propTypesLineNum = FindNextLine(lineNum, className . '.propTypes =')
  if propTypesLineNum
    let propTypes = GetLinesTo(propTypesLineNum + 1, '.*};')
    let propNames = []
    for line in propTypes
      let propName = Trim(split(line, ':')[0])
      if propName !=# '};'
        call add(propNames, propName)
      endif
    endfor
    call DeleteLines(propTypesLineNum, propTypesLineNum + len(propTypes))
    call DeleteLineIfBlank(propTypesLineNum - 1)
  endif

  let lines = ['class ' . className . ' extends Component {']

  if exists('displayName')
    let lines += [
    \ '  static displayName = ' . displayName,
    \ ''
    \ ]
  endif

  if exists('propTypes')
    call add(lines, '  static propTypes = {')
    for line in propTypes
      call add(lines, '  ' . line)
    endfor
    call add(lines, '')
  endif

  call add(lines, '  render() {')

  if exists('propTypes')
    call add(lines,
    \ '    const {' . join(propNames, ', ') . '} = this.props;')
  endif

  if !hasBlock
    call add(lines, '    return (')
  endif
  let indent = hasBlock ? '' : '  '

  for line in renderLines
    let output = len(line) ? indent . '  ' . line : line
    call add(lines, output)
  endfor

  if !hasBlock
    call add(lines, '    );')
  endif

  let lines += ['  }', '}']

  call append(lineNum - 1, lines)
endf

function! ReactToggleComponent()
  let lineNum = line('.')
  let colNum = col('.')

  let line = getline('.') " gets entire current line
  if line =~# '=>$' || line =~# '=> {$'
    call ReactFnToClass()
  elseif line =~# '^class ' || line =~# ' class '
    call ReactClassToFn()
  else
    echo 'must be on first line of a React component'
  endif

  " Move cursor back to start.
  call cursor(lineNum, colNum)
endf

" If <leader>rt for "React Toggle" is not already mapped ...
if mapcheck('\<leader>rt', 'N') ==# ''
  nnoremap <leader>rt :call ReactToggleComponent()<cr>
endif

" <c-u> removes the automatic range specification
" when command mode is entered from visual mode,
" changing the command line from :'<'> to just :

" If <leader>jc for "JSX Comment" is not already mapped ...
if mapcheck('\<leader>jc', 'N') ==# ''
  nnoremap <leader>jc :call JSXCommentRemove()<cr>
  vnoremap <leader>jc :<c-u>call JSXCommentAdd()<cr>
endif
