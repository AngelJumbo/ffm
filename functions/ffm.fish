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
	echo -e (set_color yellow)"Warning: fzf version $current_fzf_version detected, but >= $required_fzf_version is recommended. The preview feature might not work as expected."(set_color normal)
    end

    set -l dir (pwd)
    set show_hidden 1
    set -l files_cmd ""
    
    # Global clipboard variables (shared across function calls)
    if not set -q __ffm_clipboard_path
        set -g __ffm_clipboard_path ""
        set -g __ffm_clipboard_operation ""
    end
    
    while true

        if test $show_hidden -eq 1
            set files_cmd "ls --color=always --group-directories-first -A '$dir'"
        else
            set files_cmd "ls --color=always --group-directories-first '$dir'"
        end
        
        # Create temp file for special commands
        set -l temp_file (mktemp)
        
        # Create prompt with abbreviated path (last 2 directories)
        set -l prompt_path (echo $dir | sed 's|.*/\([^/]*/[^/]*\)$|\1|')
        if test "$prompt_path" = "$dir"
            # If path is short, just remove leading slash if present
            set prompt_path (echo $dir | sed 's|^/||')
        end
        
        # Create status line for clipboard
        set -l clipboard_status ""
        if test -n "$__ffm_clipboard_path"
            set -l clipboard_name (basename "$__ffm_clipboard_path")
            if test "$__ffm_clipboard_operation" = "copy"
                set clipboard_status "Copied: $clipboard_name"
            else if test "$__ffm_clipboard_operation" = "cut"
                set clipboard_status "Cut: $clipboard_name"
            end
        end
        
        # Preview command that uses the current $dir variable
        set -l preview_cmd "fish -c '
            set full_path \"$dir/{r}\"
            if test -d \"\$full_path\"
                if command -v exa >/dev/null
                    exa --color=always --icons --group-directories-first \"\$full_path\"
                else
                    ls -1 \"\$full_path\"
                end
            else
                # Get MIME type
                set mimetype (file --brief --mime-type -- \"\$full_path\" 2>/dev/null)
                switch \$mimetype
                    case \"text/plain\" \"text/x-*\"
                        if command -v bat >/dev/null
                            bat --color=always --style=plain --line-range=:20 \"\$full_path\" 2>/dev/null
                        else
                            head -20 \"\$full_path\" 2>/dev/null
                        end
                    case \"image/*\"
                        if command -v chafa >/dev/null
                            chafa --size=40x20 \"\$full_path\"
                        else
                            echo \"Image preview not available\"
                        end
                    case \"video/*\"
                        echo \"Video: \"\$full_path\"\"
                        if command -v ffprobe >/dev/null
                            ffprobe -v error -show_format -show_streams \"\$full_path\" | head -20
                        else
                            echo \"Install ffprobe for video info\"
                        end
                    case \"inode/x-empty\"
                        echo \"Empty file\"
                    case \"*\"
                        echo \"Preview not available\"
                        echo \"File: \"\$full_path\"\"
                        set file_size (stat -c%s \"\$full_path\" 2>/dev/null || stat -f%z \"\$full_path\" 2>/dev/null || echo \"0\")
                        echo \"Size: \$file_size bytes\"
                        set file_perms (stat -c%A \"\$full_path\" 2>/dev/null || stat -f%Sp \"\$full_path\" 2>/dev/null || echo \"unknown\")
                        echo \"Permissions: \$file_perms\"
                        set file_modified (stat -c%y \"\$full_path\" 2>/dev/null || stat -f%Sm \"\$full_path\" 2>/dev/null || echo \"unknown\")
                        echo \"Modified: \$file_modified\"
                end
            end
        '"

        # Run fzf with organized preview command
        set -l result (eval $files_cmd | \
            fzf \
                --ansi \
                --preview "$preview_cmd" \
                --preview-window=right:50%:wrap \
                --height=15 \
                --layout=reverse \
                --border=rounded \
                --bind "ctrl-j:down" \
                --bind "ctrl-k:up" \
                --bind "ctrl-h:execute(echo 'PARENT' > $temp_file)+abort" \
                --bind "ctrl-l:accept" \
                --bind "ctrl-r:execute(echo 'RENAME:{}' > $temp_file)+abort" \
                --bind "ctrl-y:execute(echo 'COPY:{}' > $temp_file)+abort" \
                --bind "ctrl-x:execute(echo 'CUT:{}' > $temp_file)+abort" \
                --bind "ctrl-p:execute(echo 'PASTE' > $temp_file)+abort" \
                --bind "ctrl-d:execute(echo 'DELETE:{}' > $temp_file)+abort" \
                --bind "f2:execute(echo 'TOGGLE_HIDDEN' > $temp_file)+abort"\
                --bind "alt-.:execute(echo 'TOGGLE_HIDDEN' > $temp_file)+abort"\
                --bind "down:down" \
                --bind "up:up" \
                --bind "left:execute(echo 'PARENT' > $temp_file)+abort" \
                --bind "right:accept" \
                --bind "ctrl-c:abort" \
                --bind "esc:abort" \
                --pointer='▶' \
                --marker='●' \
                --prompt="$prompt_path/")
        
        # Check for special commands
        if test -f $temp_file
            set -l command (cat $temp_file)
            rm $temp_file
            
            if test "$command" = "PARENT"
                set dir (realpath "$dir/..")
                continue
            else if string match -q "RENAME:*" $command
                # Extract filename from command
                set -l filename (string sub -s 8 $command)
                set -l clean_filename (echo $filename | sed 's/\x1b\[[0-9;]*m//g')
                set -l old_path "$dir/$clean_filename"
                
                # Check if file exists
                if test -e "$old_path"
                  #echo "Current name: $clean_filename"
                    read -P "Enter new name: " new_name
                    
                    if test -n "$new_name"
                        set -l new_path "$dir/$new_name"
                        
                        # Check if new name already exists
                        if test -e "$new_path"
                            echo "Error: '$new_name' already exists!"
                        else
                            # Perform the rename
                            if not mv "$old_path" "$new_path"
                                echo "Error: Failed to rename '$clean_filename'"
                            end
                        end
                    else
                        echo "Rename cancelled."
                    end
                else
                    echo "Error: File '$clean_filename' not found!"
                end
                continue
            else if string match -q "COPY:*" $command
                # Extract filename from command
                set -l filename (string sub -s 6 $command)
                set -l clean_filename (echo $filename | sed 's/\x1b\[[0-9;]*m//g')
                set -l file_path "$dir/$clean_filename"
                
                if test -e "$file_path"
                    set -g __ffm_clipboard_path "$file_path"
                    set -g __ffm_clipboard_operation "copy"
                else
                    echo "Error: File '$clean_filename' not found!"
                end
                continue
            else if string match -q "CUT:*" $command
                # Extract filename from command
                set -l filename (string sub -s 5 $command)
                set -l clean_filename (echo $filename | sed 's/\x1b\[[0-9;]*m//g')
                set -l file_path "$dir/$clean_filename"
                
                if test -e "$file_path"
                    set -g __ffm_clipboard_path "$file_path"
                    set -g __ffm_clipboard_operation "cut"
                else
                    echo "Error: File '$clean_filename' not found!"
                end
                continue
            else if test "$command" = "PASTE"
                if test -z "$__ffm_clipboard_path"
                    continue
                end
                
                if not test -e "$__ffm_clipboard_path"
                    echo "Error: Source file no longer exists!"
                    set -g __ffm_clipboard_path ""
                    set -g __ffm_clipboard_operation ""
                    continue
                end
                
                set -l source_name (basename "$__ffm_clipboard_path")
                set -l dest_path "$dir/$source_name"
                
                # Check if destination already exists
                if test -e "$dest_path"
                    echo "Error: '$source_name' already exists in this directory!"
                    continue
                end
                
                if test "$__ffm_clipboard_operation" = "copy"
                    # Copy operation
                    if test -d "$__ffm_clipboard_path"
                        if not cp -r "$__ffm_clipboard_path" "$dest_path"
                            echo "Error: Failed to copy directory '$source_name'"
                        end
                    else
                        if not cp "$__ffm_clipboard_path" "$dest_path"
                            echo "Error: Failed to copy file '$source_name'"
                        end
                    end
                else if test "$__ffm_clipboard_operation" = "cut"
                    # Move operation
                    if mv "$__ffm_clipboard_path" "$dest_path"
                        # Clear clipboard after successful cut operation
                        set -g __ffm_clipboard_path ""
                        set -g __ffm_clipboard_operation ""
                    else
                        echo "Error: Failed to move '$source_name'"
                    end
                end
                
                continue
            else if test "$command" = "TOGGLE_HIDDEN"
                set show_hidden (math "1 - $show_hidden")

                continue
                 
        else if string match -q "DELETE:*" $command
            set -l filename (string sub -s 8 $command)
            set -l clean_filename (echo $filename | sed 's/\x1b\[[0-9;]*m//g')
            set -l full_path "$dir/$clean_filename"
        
            if not test -e "$full_path"
            echo "Error: File '$clean_filename' not found!"
            continue
            end
        
            read -P "Are you sure you want to delete '$clean_filename'? [y/N] " confirm
            switch $confirm
            case y Y
                if rm -rf "$full_path"
                echo "'$clean_filename' deleted."
                else
                echo "Error: Failed to delete '$clean_filename'"
                end
            case '*'
                echo "Deletion cancelled."
            end
            continue
            end
        
        end
        
        # Clean up temp file
        test -f $temp_file && rm $temp_file
        
        # Handle normal exit (ctrl-c, esc)
        if test -z "$result"
            cd "$dir"
            return
        end
        
        # Strip color codes from result to get actual filename
        set -l clean_result (echo "$result" | sed 's/\x1b\[[0-9;]*m//g')
        
        # Handle selection
        set -l path "$dir/$clean_result"
        if test -d "$path"
            set dir (realpath "$path")
        else if test -f "$path"
            xdg-open "$path" >/dev/null 2>&1 &
        end
    end
end

