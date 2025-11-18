# Fish completion for pix command

complete -c pix -e
complete -c pix -f -d "Pipelines for buildx"

# Function to get available pipelines
function __pix_get_pipelines
    command pix __complete_fish pipeline 2>/dev/null
end

# Function to get available targets for a pipeline
function __pix_get_run_targets
    set --local cmd_tokens (commandline --tokens-expanded)

    # Pipeline should be the last argument
    set pipeline $cmd_tokens[-1]

    command pix __complete_fish target $pipeline 2>/dev/null
end

# Function to get available args for a target of a pipeline
function __pix_get_run_target_args
    set --local cmd_tokens (commandline --tokens-expanded)

    # Pipeline should be the last argument
    set pipeline $cmd_tokens[-1]

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
complete -c pix -n "__fish_seen_subcommand_from graph" -l "format" -d "Output format" -a "pretty dot"

# run command options
complete -c pix -n "__fish_seen_subcommand_from run" -a "(__pix_get_pipelines)" -d "Pipeline"
complete -c pix -n "__fish_seen_subcommand_from run" -l "output" -d "Output the target artifacts under .pipeline/output directory"
complete -c pix -n "__fish_seen_subcommand_from run" -l "ssh" -d "Forward SSH agent to buildx build"
complete -c pix -n "__fish_seen_subcommand_from run" -l "arg" -d "Set one or more pipeline ARG (format KEY=value)" -a "(__pix_get_run_target_args)"
complete -c pix -n "__fish_seen_subcommand_from run" -l "progress" -d "Set type of progress output" -a "auto plain tty rawjson"
complete -c pix -n "__fish_seen_subcommand_from run" -l "secret" -d "Forward one or more secrets to `buildx build`"
complete -c pix -n "__fish_seen_subcommand_from run" -l "target" -d "Run PIPELINE for a specific TARGET" -a "(__pix_get_run_targets)"
complete -c pix -n "__fish_seen_subcommand_from run" -l "tag" -d "Tag the TARGET's docker image (requires --target)"
complete -c pix -n "__fish_seen_subcommand_from run" -l "no-cache" -d "Do not use cache when building the image"
complete -c pix -n "__fish_seen_subcommand_from run" -l "no-cache-filter" -d "Do not cache specified targets" -a "(__pix_get_run_targets)"

# shell command options
complete -c pix -n "__fish_seen_subcommand_from shell" -a "(__pix_get_pipelines)" -d "Pipeline"
complete -c pix -n "__fish_seen_subcommand_from shell" -l "ssh" -d "Forward SSH agent to shell container"
complete -c pix -n "__fish_seen_subcommand_from shell" -l "arg" -d "Set one or more pipeline ARG (format KEY=value)"
complete -c pix -n "__fish_seen_subcommand_from shell" -l "secret" -d "Forward one or more secrets to `buildx build`"
complete -c pix -n "__fish_seen_subcommand_from shell" -l "target" -d "The shell target"
complete -c pix -n "__fish_seen_subcommand_from shell" -l "host" -d "Bind mount the current working dir"

# upgrade command options
complete -c pix -n "__fish_seen_subcommand_from upgrade" -l "dry-run" -d "Only check if an upgrade is available"

# cache command options
complete -c pix -n "__fish_seen_subcommand_from cache" -a "info\t'Show info about the cache' update\t'Update the cache of remote git pipelines' clear\t'Clear the cache of remote git pipelines'"

# completion_script command options
complete -c pix -n "__fish_seen_subcommand_from completion_script" -a "fish" -d "Fish completion script"
