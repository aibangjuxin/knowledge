#!/bin/zsh

# notes-cli 智能补全脚本
# 使用方法：source notes-completion.zsh

_notes_cli_completion() {
    local -a commands
    commands=(
        'search:🔍 Search notes by title or content'
        's:🔍 Search notes (short)'
        'create:📝 Create a new note'
        'c:📝 Create a new note (short)'
        'create-from-file:📄 Create note from file'
        'cf:📄 Create note from file (short)'
        'export:📤 Export note to file'
        'e:📤 Export note to file (short)'
        'edit:✏️ Edit existing note'
        'list:📋 List notes'
        'l:📋 List notes (short)'
        'get:👀 Get content of specific note'
        'g:👀 Get content of specific note (short)'
        'delete:🗑️ Delete a note'
        'd:🗑️ Delete a note (short)'
        'count:📊 Count total notes'
    )

    local context state line
    typeset -A opt_args

    _arguments -C \
        '1: :->command' \
        '*: :->args' \
        && return 0

    case $state in
        command)
            _describe -t commands 'notes-cli commands' commands
            ;;
        args)
            case $line[1] in
                search|s)
                    _message "🔍 Enter search query (e.g., 'GCP', 'meeting')"
                    ;;
                create|c)
                    if [[ $CURRENT -eq 2 ]]; then
                        _message "📝 Enter note title"
                    else
                        _message "📝 Enter note content (optional)"
                    fi
                    ;;
                create-from-file|cf)
                    if [[ $CURRENT -eq 2 ]]; then
                        _message "📝 Enter note title"
                    else
                        _files -g "*.{md,txt,js,py,json,yaml,yml}"
                    fi
                    ;;
                export|e)
                    if [[ $CURRENT -eq 2 ]]; then
                        _message "📄 Enter note title to export"
                    else
                        _files
                    fi
                    ;;
                edit)
                    if [[ $CURRENT -eq 2 ]]; then
                        _message "✏️ Enter note title to edit"
                    else
                        _message "✏️ Enter new content"
                    fi
                    ;;
                get|g|delete|d)
                    _message "📄 Enter note title"
                    ;;
                list|l)
                    _message "📋 Enter limit (optional, default: 20)"
                    ;;
                count)
                    _message "📊 Count all notes"
                    ;;
            esac
            ;;
    esac
}

# 注册补全函数
compdef _notes_cli_completion notes-cli

# 如果设置了 notes 别名，也为它注册补全
if alias notes >/dev/null 2>&1; then
    compdef _notes_cli_completion notes
fi

echo "✅ notes-cli 自动补全已启用！"
echo "💡 试试输入 'notes-cli ' 然后按 Tab 键"