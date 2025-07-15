function ffm
    set -l dir (pwd)
    
    # Global clipboard variables (shared across function calls)
    if not set -q __ffm_clipboard_path
        set -g __ffm_clipboard_path ""
        set -g __ffm_clipboard_operation ""
    end
    
    while true
        # Get files in current directory with colors
        set -l files_cmd "ls -A --color=always '$dir' | sort"
        
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
            set full_path \"$dir/{}\"
            if test -d \$full_path
                if command -v exa >/dev/null
                    exa --color=always --icons --group-directories-first \$full_path
                else
                    ls -1 \$full_path
                end
            else
                if command -v bat >/dev/null
                    set bat_output (bat --color=always --style=plain --line-range=:20 \$full_path 2>&1)
                    if echo \$bat_output | grep -q \"Binary content\"
                        echo \"Preview not available\"
                    else
                        echo \$bat_output
                    end
                else
                    head -20 \$full_path 2>/dev/null || echo \"Preview not available\"
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
                --bind "down:down" \
                --bind "up:up" \
                --bind "left:execute(echo 'PARENT' > $temp_file)+abort" \
                --bind "right:accept" \
                --bind "ctrl-c:abort" \
                --bind "esc:abort" \
		#--footer "$clipboard_status" \
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
                    #echo "Copied: $clean_filename"
                    #read -P "Press Enter to continue..."
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
                  #echo "Nothing to paste!"
                  #read -P "Press Enter to continue..."
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
        set -l clean_result (echo $result | sed 's/\x1b\[[0-9;]*m//g')
        
        # Handle selection
        set -l path "$dir/$clean_result"
        if test -d "$path"
            set dir (realpath "$path")
        else if test -f "$path"
            xdg-open "$path" >/dev/null 2>&1 &
        end
    end
end
