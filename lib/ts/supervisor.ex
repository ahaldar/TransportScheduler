defmodule TS.Supervisor do
	@moduledoc """
	.
	"""
	use Supervisor

	@doc """
	Start supervisor process
	"""
	def start_link do
		Supervisor.start_link(__MODULE__, :ok)
	end

	def init(:ok) do
		children=[
			worker(StationConstructor, [StationConstructor]),
			supervisor(TS.API.Supervisor, []),
			supervisor(TS.Station.Supervisor, [])
		]
		supervise(children, strategy: :rest_for_one)
	end

end
