defmodule Palimpedia.Anchor.Source do
  @moduledoc """
  Defines an anchor corpus source — a verified external data provider.

  Layer 0: The anchor corpus is the only layer that is not generated.
  All confidence scores ultimately trace back to anchor sources.
  """

  @type source_type :: :wikidata | :arxiv | :legal | :primary_document | :custom

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t(),
          source_type: source_type(),
          base_url: String.t(),
          enabled: boolean(),
          last_sync_at: DateTime.t() | nil,
          config: map()
        }

  defstruct [
    :id,
    :name,
    :source_type,
    :base_url,
    :last_sync_at,
    enabled: true,
    config: %{}
  ]
end
