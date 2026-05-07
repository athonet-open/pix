# Fish completion for pix command

complete -c pix -e
complete -c pix -f -d "Pipelines for buildx"

# Function to find the pipeline name from the command line
# Scans tokens starting after "pix <subcommand>", returning the first non-flag positional argument
function __pix_find_pipeline
    set --local cmd_tokens (commandline --tokens-expanded)
    for i in (seq 3 (count $cmd_tokens))
        if not string match -q -- "-*" $cmd_tokens[$i]
            echo $cmd_tokens[$i]
            return
        end
    end
end

# Function to get available pipelines
function __pix_get_pipelines
    command pix __complete_fish pipeline 2>/dev/null
end

# Function to get available targets for a pipeline
function __pix_get_run_targets
    set --local pipeline (__pix_find_pipeline)

    if test -n "$pipeline"
        command pix __complete_fish target $pipeline 2>/dev/null
    end
end

# Function to get available args for a target of a pipeline
function __pix_get_run_target_args
    set --local pipeline (__pix_find_pipeline)
    set --local cmd_tokens (commandline --tokens-expanded)

    # Find index of "--target"
    set --local target_index 0
    set --local target ""

    for token in $cmd_tokens
        set target_index (math $target_index + 1)

        if string match -q -- "--target" $token
            set target $cmd_tokens[(math $target_index + 1)]
            break
        else
            if string match --quiet -- "--target=*" $token
                set target (string match --regex --groups-only -- "--target=(:?.*)" $token)
                break
            end
        end
    end

    if test -n "$target"
        command pix __complete_fish arg $pipeline $target 2>/dev/null
    end
end

# Main commands
complete -c pix -n "__fish_use_subcommand" -a "ls" -d "List the current project's pipelines"
complete -c pix -n "__fish_use_subcommand" -a "graph" -d "Prints the pipeline graph"
complete -c pix -n "__fish_use_subcommand" -a "run" -d "Run PIPELINE"
complete -c pix -n "__fish_use_subcommand" -a "shell" -d "Shell into the specified target of the PIPELINE"
complete -c pix -n "__fish_use_subcommand" -a "upgrade" -d "Upgrade pix to the latest version"
complete -c pix -n "__fish_use_subcommand" -a "cache" -d "Cache management"
complete -c pix -n "__fish_use_subcommand" -a "completion_script" -d "Completion script"
complete -c pix -n "__fish_use_subcommand" -a "help" -d "Help"

# ls command options
complete -c pix -n "__fish_seen_subcommand_from ls" -a "(__pix_get_pipelines)" -d "Pipeline"
complete -c pix -n "__fish_seen_subcommand_from ls" -l "verbose" -d "Show pipeline configuration details"
complete -c pix -n "__fish_seen_subcommand_from ls" -l "hidden" -d "Show also private pipelines targets"

# graph command options
complete -c pix -n "__fish_seen_subcommand_from graph" -a "(__pix_get_pipelines)" -d "Pipeline"
complete -c pix -n "__fish_seen_subcommand_from graph" -l "format" -rf -d "Output format" -a "pretty dot"

# run command options
complete -c pix -n "__fish_seen_subcommand_from run" -a "(__pix_get_pipelines)" -d "Pipeline"
complete -c pix -n "__fish_seen_subcommand_from run" -l "output" -d "Output the target artifacts under .pipeline/output directory"
complete -c pix -n "__fish_seen_subcommand_from run" -l "ssh" -d "Forward SSH agent/keys to buildx build (default, or id=path)" -rf
complete -c pix -n "__fish_seen_subcommand_from run" -l "arg" -rf -d "Set one or more pipeline ARG (format KEY=value)" -a "(__pix_get_run_target_args)"
complete -c pix -n "__fish_seen_subcommand_from run" -l "progress" -rf -d "Set type of progress output" -a "auto plain tty rawjson"
complete -c pix -n "__fish_seen_subcommand_from run" -l "secret" -rf -d "Forward one or more secrets to `buildx build`"
complete -c pix -n "__fish_seen_subcommand_from run" -l "target" -rf -d "Run PIPELINE for a specific TARGET" -a "(__pix_get_run_targets)"
complete -c pix -n "__fish_seen_subcommand_from run" -l "tag" -rf -d "Tag the TARGET's docker image (requires --target)"
complete -c pix -n "__fish_seen_subcommand_from run" -l "save" -d "Save the TARGET's docker image to a file (requires --target and --tag)" -rF
complete -c pix -n "__fish_seen_subcommand_from run" -l "no-cache" -d "Do not use cache when building the image"
complete -c pix -n "__fish_seen_subcommand_from run" -l "no-cache-filter" -rf -d "Do not cache specified targets" -a "(__pix_get_run_targets)"

# shell command options
complete -c pix -n "__fish_seen_subcommand_from shell" -a "(__pix_get_pipelines)" -d "Pipeline"
complete -c pix -n "__fish_seen_subcommand_from shell" -l "ssh" -d "Forward SSH agent/keys to shell container (default, or id=path)" -rf
complete -c pix -n "__fish_seen_subcommand_from shell" -l "arg" -rf -d "Set one or more pipeline ARG (format KEY=value)" -a "(__pix_get_run_target_args)"
complete -c pix -n "__fish_seen_subcommand_from shell" -l "secret" -rf -d "Forward one or more secrets to `buildx build`"
complete -c pix -n "__fish_seen_subcommand_from shell" -l "target" -rf -d "The shell target" -a "(__pix_get_run_targets)"
complete -c pix -n "__fish_seen_subcommand_from shell" -l "host" -d "Bind mount the current working dir"

# upgrade command options
complete -c pix -n "__fish_seen_subcommand_from upgrade" -l "dry-run" -d "Only check if an upgrade is available"

# cache command options
complete -c pix -n "__fish_seen_subcommand_from cache" -a "info\t'Show info about the cache' update\t'Update the cache of remote git pipelines' outdated\t'Check if cached pipelines are outdated' clear\t'Clear the cache of remote git pipelines'"

# help command options
complete -c pix -n "__fish_seen_subcommand_from help" -a "ls graph run shell upgrade cache completion_script" -d "Command"

# completion_script command options
complete -c pix -n "__fish_seen_subcommand_from completion_script" -a "fish" -d "Fish completion script"
