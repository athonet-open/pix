defmodule Pix.Pipeline.Spec.Input do
  @moduledoc """
  The input of the `c:Pix.Pipeline.Project.pipeline_spec/1` callback.

  - `:args` - the arguments of the pipeline: the `default_args` of the pipeline alias, the Pix builtins
    (`PIX_*`, except `PIX_PIPELINE_TARGET`) and, for `pix run` and `pix shell`, the `--arg` values of
    the command line, which take precedence.
  """

  @enforce_keys [:args]
  defstruct [:args]

  @type t() :: %__MODULE__{args: Pix.Config.args()}
end
