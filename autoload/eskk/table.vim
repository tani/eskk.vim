" vim:foldmethod=marker:fen:
scriptencoding utf-8

" See 'plugin/eskk.vim' about the license.

" Load once {{{
if exists('s:loaded')
    finish
endif
let s:loaded = 1
" }}}
" Saving 'cpoptions' {{{
let s:save_cpo = &cpo
set cpo&vim
" }}}
runtime! plugin/eskk.vim



" Variables {{{
let s:table_defs = {}
let s:registered_tables = {}

let s:MAP_TO_INDEX = 0
let s:REST_INDEX = 1
lockvar s:MAP_TO_INDEX
lockvar s:REST_INDEX
" }}}


" Functions {{{

" Primitive table functions {{{

" NOTE: `s:table_defs` Structure is:
" let s:table_defs['table_name'] = {
"   'name': 'base_table_name',
"   'base': {...},
"   'derived': [
"       {'method': 'add', 'data': {...}},
"       {'method': 'remove', 'data': {...}},
"       ...
"   ],
" }

function! s:load_table(table_name) "{{{
    if eskk#util#has_key_f(s:table_defs, [a:table_name, 'base'])
        call eskk#util#logf("table '%s' has been loaded.", a:table_name)
        return s:table_defs[a:table_name].base
    endif

    if eskk#util#has_key_f(s:table_defs, [a:table_name, 'lazyinit'])
        let def = call(s:table_defs[a:table_name].lazyinit, [])
        unlet s:table_defs[a:table_name].lazyinit
        let s:table_defs[a:table_name].base = def
        call eskk#util#logf("table '%s' has been loaded.", a:table_name)
        return def
    endif

    if eskk#util#has_key_f(s:table_defs, [a:table_name, 'name'])
        call eskk#util#logf("table '%s' has been loaded.", a:table_name)
        return s:load_table(s:table_defs[a:table_name].name)
    endif

    throw eskk#internal_error(['eskk', 'table'])
endfunction "}}}

function! s:get_base_table(table_name, ...) "{{{
    " For compatibility, this function returns base table object.

    if eskk#util#has_key_f(s:table_defs, [a:table_name, 'base'])
        return s:table_defs[a:table_name].base
    endif

    " Lazy loading.
    call s:load_table(a:table_name)
    return s:table_defs[a:table_name].base
endfunction "}}}

function! s:has_table(table_name) "{{{
    call s:load_table(a:table_name)    " to load this table.
    return has_key(s:table_defs, a:table_name)
endfunction "}}}

function! s:set_derived_table(table_name, derived_dict, base_table_name) "{{{
    if has_key(s:table_defs, a:table_name)
        " Do not allow override table.
        let msg = printf("'%s' has been already registered.", a:table_name)
        throw eskk#internal_error(['eskk', 'table'], msg)
    endif

    let s:table_defs[a:table_name] = {}
    let def = s:table_defs[a:table_name]

    " NOTE: I don't set `def.base` here.
    " It will be set in `s:get_base_table()`.
    let def.name = a:base_table_name
    let def.derived = a:derived_dict
endfunction "}}}
function! s:set_base_table(table_name, Fn) "{{{
    if has_key(s:table_defs, a:table_name)
        " Do not allow override table.
        let msg = printf("'%s' has been already registered.", a:table_name)
        throw eskk#internal_error(['eskk', 'table'], msg)
    endif

    let s:table_defs[a:table_name] = {}
    let def = s:table_defs[a:table_name]

    let def.name = a:table_name
    let def.lazyinit = a:Fn
endfunction "}}}

function! s:is_base_table(table_name) "{{{
    call s:load_table(a:table_name)
    return s:table_defs[a:table_name].name ==# a:table_name
endfunction "}}}

function! s:get_map(table_name, search_lhs, index, ...) "{{{
    if s:is_base_table(a:table_name)
        return call('eskk#util#get_f', [s:get_base_table(a:table_name), [a:search_lhs, a:index]] + a:000)
    else
        let derived = s:table_defs[a:table_name].derived
        let derived_result = {}    " key is lhs.
        " Process each derived List elements *in order*.
        " NOTE: Do not return inside `:for`.
        for i in range(len(derived))
            if has_key(derived[i].data, a:search_lhs)
                if derived[i].method ==# 'add'
                    let derived_result[a:search_lhs] = derived[i].data[a:search_lhs][a:index]
                elseif derived[i].method ==# 'remove'
                    if has_key(derived_result, a:search_lhs)
                        unlet derived_result[a:search_lhs]
                    endif
                else
                    let msg = "`method` key's value is one of 'add', 'remove'."
                    throw eskk#internal_error(['eskk', 'table'], msg)
                endif
            endif
        endfor
        if has_key(derived_result, a:search_lhs)
            return derived_result[a:search_lhs]
        endif

        " No map in `derived`. Look up in base dict.
        return call('s:get_map', [s:table_defs[a:table_name].name, a:search_lhs, a:index] + a:000)
    endif

    " No lhs in `s:table_defs`.
    if a:0
        return a:1
    else
        throw eskk#internal_error(['eskk', 'table'])
    endif
endfunction "}}}

function! s:has_map(table_name, lhs, index) "{{{
    let no_map = {}
    return s:get_map(a:table_name, a:lhs, a:index, no_map) isnot no_map
endfunction "}}}

" }}}


" Autoload functions for writing table. {{{

function! eskk#table#register_derived_table_dict(...) "{{{
    call call('s:set_derived_table', a:000)
endfunction "}}}
function! eskk#table#register_table_dict(...) "{{{
    call call('s:set_base_table', a:000)
endfunction "}}}

" }}}


" Autoload functions {{{

function! eskk#table#has_candidates(...) "{{{
    return !empty(call('eskk#table#get_candidates', a:000))
endfunction "}}}

function! eskk#table#get_candidates(table_name, str_buf) "{{{
    if empty(a:str_buf)
        throw eskk#internal_error(['eskk', 'table'], "a:str_buf is empty.")
    endif

    if !s:has_table(a:table_name)
        return {}
    else
        return filter(
        \   keys(s:get_base_table(a:table_name)),
        \   'stridx(v:val, a:str_buf) == 0'
        \)
    endif
endfunction "}}}


function! eskk#table#has_table(table_name) "{{{
    return s:has_table(a:table_name)
endfunction "}}}

function! eskk#table#has_map(table_name, lhs) "{{{
    return call('s:has_map', [a:table_name, a:lhs, s:MAP_TO_INDEX])
endfunction "}}}


function! eskk#table#get_map_to(table_name, lhs, ...) "{{{
    return call('s:get_map', [a:table_name, a:lhs, s:MAP_TO_INDEX] + a:000)
endfunction "}}}


function! eskk#table#has_rest(table_name, lhs) "{{{
    return call('s:has_map', [a:table_name, a:lhs, s:REST_INDEX])
endfunction "}}}

function! eskk#table#get_rest(table_name, lhs, ...) "{{{
    return call('s:get_map', [a:table_name, a:lhs, s:REST_INDEX] + a:000)
endfunction "}}}


function! eskk#table#get_definition(table_name) "{{{
    return s:get_base_table(a:table_name)
endfunction "}}}

function! eskk#table#get_table(table_name) "{{{
    let varname = 's:lazy_table_' . a:table_name
    if exists(varname)
        return {varname}
    else
        let {varname} = eskk#table#new(a:table_name)
        return {varname}
    endif
endfunction "}}}

" }}}


" OO interface {{{
let s:table_obj = {}

function! eskk#table#new(table_name) "{{{
    let obj = deepcopy(s:table_obj)
    let obj.table_name = a:table_name

    return obj
endfunction "}}}


" I need meta programming in Vim script!!

function! s:table_obj.has_candidates(...) dict "{{{
    return call('eskk#table#has_candidates', [self.table_name] + a:000)
endfunction "}}}

function! s:table_obj.get_candidates(...) dict "{{{
    return call('eskk#table#get_candidates', [self.table_name] + a:000)
endfunction "}}}

function! s:table_obj.has_map(...) dict "{{{
    return call('eskk#table#has_map', [self.table_name] + a:000)
endfunction "}}}

function! s:table_obj.get_map_to(...) dict "{{{
    return call('eskk#table#get_map_to', [self.table_name] + a:000)
endfunction "}}}

function! s:table_obj.has_rest(...) dict "{{{
    return call('eskk#table#has_rest', [self.table_name] + a:000)
endfunction "}}}

function! s:table_obj.get_rest(...) dict "{{{
    return call('eskk#table#get_rest', [self.table_name] + a:000)
endfunction "}}}


lockvar s:table_obj
" }}}

" }}}


" Restore 'cpoptions' {{{
let &cpo = s:save_cpo
" }}}
