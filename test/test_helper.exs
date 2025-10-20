Application.put_env(:icu, :default_locale, "en-US")
ExUnit.start()

# Path.wildcard(Path.join(__DIR__, "support/**/*.ex"))
# |> Enum.each(&Code.require_file/1)

# nif_available? =
#  try do
#    {:ok, _} = Icu.LanguageTag.parse("en")
#    true
#  rescue
#    _ -> false
#  end
#
# unless nif_available? do
#  ExUnit.configure(exclude: [requires_nif: true])
# end
