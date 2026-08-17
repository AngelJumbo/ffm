function ffm
    set -l required_fzf_version "0.64.0"
    set -l current_fzf_version (string split " " (fzf --version))[1]

    function __version_gte
        set -l a (string split . $argv[1])
        set -l b (string split . $argv[2])

        for i in (seq (count $a))
            set -l ai $a[$i]
            set -l bi (math "0 + $b[$i]")

            if test (math "$ai") -gt $bi
                return 0
            else if test (math "$ai") -lt $bi
                return 1
            end
        end

        return 0
    end

    if not __version_gte $current_fzf_version $required_fzf_version
        echo -e (set_color yellow)"Warning: fzf version $current_fzf_version detected, but >= $required_fzf_version is recommended."(set_color normal)
    end

    set -l state_dir (mktemp -d)
    echo (pwd) > $state_dir/dir
    echo 1 > $state_dir/hidden
    touch $state_dir/clip_path $state_dir/clip_op
    set -x FFM_STATE $state_dir

    set -l prompt_path (string replace -r '.*/([^/]*/[^/]*)$' '$1' -- (pwd))
    if test "$prompt_path" = (pwd)
        set prompt_path (string replace -r '^/' '' -- (pwd))
    end

    eval "ls --color=always --group-directories-first -A -- '"(pwd)"'" | \
        fzf \
            --ansi \
            --preview 'fish -c "__ffm_helper preview {}"' \
            --preview-window=right:50%:wrap \
            --height=15 \
            --layout=reverse \
            --border=rounded \
            --prompt="$prompt_path/" \
            --bind "ctrl-j:down" --bind "ctrl-k:up" \
            --bind "ctrl-h:execute-silent(fish -c '__ffm_helper parent')+reload(fish -c '__ffm_helper list')+transform-prompt(fish -c '__ffm_helper prompt')+clear-query" \
            --bind "left:execute-silent(fish -c '__ffm_helper parent')+reload(fish -c '__ffm_helper list')+transform-prompt(fish -c '__ffm_helper prompt')+clear-query" \
            --bind "ctrl-l:execute-silent(fish -c '__ffm_helper enter {}')+reload(fish -c '__ffm_helper list')+transform-prompt(fish -c '__ffm_helper prompt')+clear-query" \
            --bind "right:execute-silent(fish -c '__ffm_helper enter {}')+reload(fish -c '__ffm_helper list')+transform-prompt(fish -c '__ffm_helper prompt')+clear-query" \
            --bind "enter:execute-silent(fish -c '__ffm_helper enter {}')+reload(fish -c '__ffm_helper list')+transform-prompt(fish -c '__ffm_helper prompt')+clear-query" \
            --bind "ctrl-r:execute(fish -c '__ffm_helper rename {}')+reload(fish -c '__ffm_helper list')" \
            --bind "ctrl-y:execute-silent(fish -c '__ffm_helper copy {}')" \
            --bind "ctrl-x:execute-silent(fish -c '__ffm_helper cut {}')" \
            --bind "ctrl-p:execute(fish -c '__ffm_helper paste')+reload(fish -c '__ffm_helper list')" \
            --bind "ctrl-d:execute(fish -c '__ffm_helper delete {}')+reload(fish -c '__ffm_helper list')" \
            --bind "f2:execute-silent(fish -c '__ffm_helper toggle_hidden')+reload(fish -c '__ffm_helper list')" \
            --bind "alt-.:execute-silent(fish -c '__ffm_helper toggle_hidden')+reload(fish -c '__ffm_helper list')" \
            --bind "down:down" --bind "up:up" \
            --bind "ctrl-c:abort" --bind "esc:abort" \
            --pointer='▶' --marker='●' \
            > /dev/null

    cd (cat $state_dir/dir)
    rm -rf $state_dir
end
