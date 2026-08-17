function __ffm_helper
    set -l state $FFM_STATE
    set -l action $argv[1]

    function __ffm_read_prompt
        set -l prompt_text $argv[1]
        set -l input_value

        if test -t 0
            read --prompt "$prompt_text" input_value
        else if test -e /dev/tty
            printf '%s' "$prompt_text" > /dev/tty
            read input_value < /dev/tty 2>/dev/null
        else
            echo "$prompt_text" >&2
            read input_value
        end

        printf '%s' "$input_value"
    end

    switch $action
        case list
            set -l dir (cat $state/dir)
            if test (cat $state/hidden) = 1
                ls --color=always --group-directories-first -A -- "$dir"
            else
                ls --color=always --group-directories-first -- "$dir"
            end

        case prompt
            set -l dir (cat $state/dir)
            set -l p (string replace -r '.*/([^/]*/[^/]*)$' '$1' -- $dir)
            if test "$p" = "$dir"
                set p (string replace -r '^/' '' -- $dir)
            end
            echo "$p/"

        case preview
            set -l dir (cat $state/dir)
            set -l name (string replace -ra '\x1b\[[0-9;]*m' '' -- $argv[2])
            set -l full_path "$dir/$name"

            if test -d "$full_path"
                if command -v exa >/dev/null
                    exa --color=always --icons --group-directories-first "$full_path"
                else
                    ls -1 "$full_path"
                end
            else
                set -l mimetype (file --brief --mime-type -- "$full_path" 2>/dev/null)
                switch $mimetype
                    case "text/plain" "text/x-*"
                        if command -v bat >/dev/null
                            bat --color=always --style=plain --line-range=:20 "$full_path" 2>/dev/null
                        else
                            head -20 "$full_path" 2>/dev/null
                        end
                    case "image/*"
                        if command -v chafa >/dev/null
                            chafa --size=40x20 "$full_path"
                        else
                            echo "Image preview not available"
                        end
                    case "video/*"
                        echo "Video: $full_path"
                        if command -v ffprobe >/dev/null
                            ffprobe -v error -show_format -show_streams "$full_path" | head -20
                        else
                            echo "Install ffprobe for video info"
                        end
                    case "inode/x-empty"
                        echo "Empty file"
                    case '*'
                        echo "Preview not available"
                        echo "File: $full_path"
                        set -l sz (stat -c%s "$full_path" 2>/dev/null; or stat -f%z "$full_path" 2>/dev/null; or echo 0)
                        echo "Size: $sz bytes"
                        set -l perms (stat -c%A "$full_path" 2>/dev/null; or stat -f%Sp "$full_path" 2>/dev/null; or echo unknown)
                        echo "Permissions: $perms"
                        set -l mod (stat -c%y "$full_path" 2>/dev/null; or stat -f%Sm "$full_path" 2>/dev/null; or echo unknown)
                        echo "Modified: $mod"
                end
            end

        case enter
            set -l dir (cat $state/dir)
            set -l name (string replace -ra '\x1b\[[0-9;]*m' '' -- $argv[2])
            set -l full_path "$dir/$name"

            if test -d "$full_path"
                realpath "$full_path" > $state/dir
            else if test -f "$full_path"
                xdg-open "$full_path" >/dev/null 2>&1 &
                disown
            end

        case parent
            set -l dir (cat $state/dir)
            realpath "$dir/.." > $state/dir

        case toggle_hidden
            if test (cat $state/hidden) = 1
                echo 0 > $state/hidden
            else
                echo 1 > $state/hidden
            end

        case rename
            set -l dir (cat $state/dir)
            set -l name (string replace -ra '\x1b\[[0-9;]*m' '' -- $argv[2])
            set -l old_path "$dir/$name"

            if test -e "$old_path"
                set -l new_name (__ffm_read_prompt "Enter new name: ")
                if test -n "$new_name"
                    set -l new_path "$dir/$new_name"
                    if test -e "$new_path"
                        echo "Error: '$new_name' already exists!"
                        __ffm_read_prompt "Press enter..." >/dev/null
                    else if not mv "$old_path" "$new_path"
                        echo "Error: Failed to rename '$name'"
                        __ffm_read_prompt "Press enter..." >/dev/null
                    end
                end
            else
                echo "Error: File '$name' not found!"
                __ffm_read_prompt "Press enter..." >/dev/null
            end

        case copy
            set -l dir (cat $state/dir)
            set -l name (string replace -ra '\x1b\[[0-9;]*m' '' -- $argv[2])
            set -l full_path "$dir/$name"
            if test -e "$full_path"
                echo "$full_path" > $state/clip_path
                echo copy > $state/clip_op
            end

        case cut
            set -l dir (cat $state/dir)
            set -l name (string replace -ra '\x1b\[[0-9;]*m' '' -- $argv[2])
            set -l full_path "$dir/$name"
            if test -e "$full_path"
                echo "$full_path" > $state/clip_path
                echo cut > $state/clip_op
            end

        case paste
            test -s $state/clip_path; or exit 0
            set -l clip_path (cat $state/clip_path)
            set -l clip_op (cat $state/clip_op)
            set -l dir (cat $state/dir)

            if not test -e "$clip_path"
                echo "Error: Source file no longer exists!"
                : > $state/clip_path; : > $state/clip_op
                __ffm_read_prompt "Press enter..." >/dev/null
                return
            end

            set -l source_name (basename "$clip_path")
            set -l dest_path "$dir/$source_name"

            if test -e "$dest_path"
                echo "Error: '$source_name' already exists here!"
                __ffm_read_prompt "Press enter..." >/dev/null
            else if test "$clip_op" = copy
                if test -d "$clip_path"
                    cp -r "$clip_path" "$dest_path"; or echo "Error copying directory"
                else
                    cp "$clip_path" "$dest_path"; or echo "Error copying file"
                end
            else if test "$clip_op" = cut
                if mv "$clip_path" "$dest_path"
                    : > $state/clip_path; : > $state/clip_op
                else
                    echo "Error: Failed to move '$source_name'"
                    __ffm_read_prompt "Press enter..." >/dev/null
                end
            end

        case delete
            set -l dir (cat $state/dir)
            set -l name (string replace -ra '\x1b\[[0-9;]*m' '' -- $argv[2])
            set -l full_path "$dir/$name"

            if not test -e "$full_path"
                echo "Error: File '$name' not found!"
                __ffm_read_prompt "Press enter..." >/dev/null
            else
                set -l confirm (__ffm_read_prompt "Delete '$name'? [y/N] ")
                switch "$confirm"
                    case y Y
                        if rm -rf "$full_path"
                            echo "'$name' deleted."
                        else
                            echo "Error: Failed to delete '$name'"
                            __ffm_read_prompt "Press enter..." >/dev/null
                        end
                    case '*'
                        echo "Cancelled."
                end
            end
    end
end
