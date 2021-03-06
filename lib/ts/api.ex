defmodule API do
	@moduledoc """
	Module to define RESTful API using Maru library. cURL requests can be handled
	and appropriate	response in JSON format can be returned to the user. This API
	is used to obtain and update station variables and find the best itinerary.

	Uses Maru, GenServer.
	"""
	use Maru.Router, make_plug: true
	use Maru.Type
	use GenServer, async: true

	before do
		plug Plug.Parsers,
		pass: ["*/*"],
		json_decoder: Poison,
		parsers: [:json]
	end

	namespace :api do
		get do
			StationConstructor.start_link(:NC)
			API.start_link
			{:ok, pid}=InputParser.start_link
			stn_map=InputParser.get_station_map(pid)
			for stn_key<-Map.keys(stn_map) do
				stn_code=Map.get(stn_map, stn_key)
				stn_struct=InputParser.get_station_struct(pid, stn_key)
				StationConstructor.create(StationConstructor, stn_key, stn_code)
				{:ok, {_, station}}=StationConstructor.lookup_name(StationConstructor,
					stn_key)
				Station.update(station, stn_struct)
			end
			conn|>put_status(200)|>text("Welcome to TransportScheduler API\n")
		end

		namespace :search do
			desc "get itinerary from source to destination"
			params do
				requires :source, type: Integer
				requires :destination, type: Integer
				requires :start_time, type: Integer
				requires :end_time, type: Integer
				requires :date, type: String
			end

			get do
				# Obtain itinerary
				query=%{src_station: params[:source], dst_station: params[:destination],
				arrival_time: params[:start_time], end_time: params[:end_time]}
				{:ok, {_, stn}}=StationConstructor.lookup_code(StationConstructor,
					params[:source])
				API.put(conn, query, [])
				API.put({"times", query}, [])
				StationConstructor.add_query(StationConstructor, query, conn)
				itinerary=[Map.put(query, :day, 0)]
				{:ok, pid}=QC.start_link
				API.put(query, {self(), pid, System.system_time(:milliseconds)})
				StationConstructor.send_to_src(StationConstructor, stn, itinerary)
				Process.send_after(self(), :timeout, 30_000)
				receive do
					:timeout->
						StationConstructor.del_query(StationConstructor, query)
						final=conn|>API.get|>sort_list
						resp=final|>List.last|>List.last|>Map.get(:arrival_time)
						days=final|>List.first|>List.first|>Map.get(:day)
						conn|>put_status(200)|>json(days*86_400+resp)
						f=File.open!("data/times.csv", [:append])
						IO.write(f, CSVLixir.write_row(API.get({"times", query})))
						File.close(f)
						API.remove({"times", query})
						API.remove(conn)
						API.remove(query)
						QC.stop(pid)
					:release->
						final=conn|>API.get|>sort_list
						resp=final|>List.last|>List.last|>Map.get(:arrival_time)
						days=final|>List.first|>List.first|>Map.get(:day)
						conn|>put_status(200)|>json(days*86_400+resp)
						f=File.open!("data/times.csv", [:append])
						IO.write(f, CSVLixir.write_row(API.get({"times", query})))
						File.close(f)
						API.remove({"times", query})
						API.remove(conn)
						API.remove(query)
						QC.stop(pid)
				end
			end
		end

		namespace :station do
			namespace :schedule do
				@desc "get a station\'s schedule"
				params do
					requires :station_code, type: Integer
					requires :date, type: String
				end

				get do
					# Get schedule
					{:ok, {_, station}}=StationConstructor.lookup_code(StationConstructor,
					params[:station_code])
					st_str=Station.get_vars(station)
					res=Map.fetch!(st_str, :schedule)
					conn|>put_status(200)|>json(res)
				end

				namespace :add do
					@desc "add an entry to a station\'s schedule"
					params do
						requires :entry, type: Map do
							requires :vehicleID, type: String
							requires :src_station, type: Integer
							requires :dst_station, type: Integer
							requires :dept_time, type: Integer
							requires :arrival_time, type: Integer
							requires :mode_of_transport, type: String
						end
					end

					post do
						# Add New Schedule
						entry_map=params[:entry]
						{:ok, {_, station}}=StationConstructor.
						lookup_code(StationConstructor, entry_map.src_station)
						st_str=Station.get_vars(station)
						stn_sched=List.insert_at(st_str.schedule, 0, entry_map)
						st_str=%{st_str|schedule: stn_sched}
						Station.update(station, st_str)
						conn|>put_status(201)|>text("New Schedule added!\n")
					end
				end

				namespace :update do
					@desc "update an existing entry in the station\'s schedule"
					params do
						requires :entry, type: Map do
							requires :vehicleID, type: String
							requires :src_station, type: Integer
							requires :dst_station, type: Integer
							requires :dept_time, type: Integer
							requires :arrival_time, type: Integer
							requires :mode_of_transport, type: String
						end
					end

					put do
						# Update Schedule
						entry_map=params[:entry]
						{:ok, {_, station}}=StationConstructor.
						lookup_code(StationConstructor, entry_map.src_station)
						st_str=Station.get_vars(station)
						stn_sched=update_list(st_str.schedule, [], entry_map.vehicleID,
							entry_map, length(st_str.schedule))
						st_str=%{st_str|schedule: stn_sched}
						Station.update(station, st_str)
						conn|>put_status(202)|>text("Schedule Updated!\n")
					end
				end
			end

			namespace :state do
				@desc "get state of a station"
				params do
					requires :station_code, type: Integer
				end
				get do
					# Get state vars of that station
					{:ok, {_, station}}=StationConstructor.lookup_code(StationConstructor,
					params[:station_code])
					st_str=Station.get_vars(station)
					conn|>put_status(200)|>json(st_str.loc_vars)
				end

				namespace :update do
					@desc "update state of a station"
					params do
						requires :station_code, type: Integer
						requires :local_vars, type: Map do
							requires :congestion, type: String, values: ["none", "low",
							"high"], default: "none"
							requires :delay, type: Float
							requires :disturbance, type: String, values: ["yes", "no"],
							default: "no"
						end
					end
					put do
						# Update state vars of that station
						{:ok, {_, station}}=StationConstructor.
						lookup_code(StationConstructor, params[:station_code])
						st_str=Station.get_vars(station)
						loc_var_map=Map.put(params[:local_vars], :congestion_delay, nil)
						st_str=%{st_str|loc_vars: loc_var_map}
						Station.update(station, st_str)
						conn|>put_status(202)|>text("State Updated!\n")
					end
				end
			end

			namespace :create do
				desc "create a new station"
				params do
					requires :local_vars, type: Map do
						requires :congestion, type: String, values: ["none", "low", "high"],
						 default: "none"
						requires :delay, type: Float
						requires :disturbance, type: String, values: ["yes", "no"],
						default: "no"
					end
					requires :schedule, type: Map do
							requires :vehicleID, type: String
							requires :src_station, type: Integer
							requires :dst_station, type: Integer
							requires :dept_time, type: Integer
							requires :arrival_time, type: Integer
							requires :mode_of_transport, type: String
						#end
					end
					requires :station_code, type: Integer
					requires :station_name, type: String
				end

				post do
					# Add new station's details
					StationConstructor.create(StationConstructor, params[:station_name],
						params[:station_code])
					{:ok, {_, station}}=StationConstructor.lookup_code(StationConstructor,
					params[:station_code])
					loc_var_map=Map.put(params[:local_vars], :congestion_delay, nil)
					stn_str=%StationStruct{loc_vars: loc_var_map, schedule:
					[params[:schedule]], station_number: params[:station_code],
					station_name: params[:station_name]}
					Station.update(station, stn_str)
					conn|>put_status(201)|>text("New Station created!\n")
				end
			end
		end
	end

	rescue_from Maru.Exceptions.NotFound do
		conn|>put_status(404)|>json(%{error: "Entry not found"})
	end

	rescue_from Maru.Exceptions.InvalidFormat do
		conn|>put_status(400)|>json(%{error: "Invalid request format"})
	end

	rescue_from Maru.Exceptions.MethodNotAllowed do
		conn|>put_status(405)|>json(%{error: "Method not allowed"})
	end

	rescue_from [MatchError] do
		conn|>put_status(400)|>json(%{error: "Invalid data"})
	end

	rescue_from :all do
		conn|>put_status(500)|>json(%{error: "Server Error"})
	end

	@doc """
	This function is called by Query Collector in order to add an itinerary to
	the list of received itineraries returned from Station Constructor. In
	`collect/2` function of QC, this function is called to add all returned
	queries to the list as they come in.

	The API function check whether the number of itineraries received is crossing
	the limit of maximum itineraries required. If limit is reached, query is
	deleted form the map of active queries. Otherwise, itinerary is added to the
	list of itineraries collected for a given query.

	### Parameters
	queries - in the form of a map	`%{src_station, dst_station, arrival_time,
	end_time}`.

	itinerary - in the form of a map `%{vehicleID, src_station, dst_station,
	dept_time, arrival_time, mode_of_transport}`.

	### Return values
	Returns {:ok}
	"""
	def add_itinerary(queries, itinerary) do
		API.start_link
		queries=if length(Map.keys(queries))!=0 do
			query=itinerary|>List.first|>Map.delete(:day)
			conn=Map.get(queries, query)
			list=API.get(conn)
			times=API.get({"times", query})
			bool=if list===nil do
				false
			else
				(length(list)<15)
			end
			case bool do
				true->
					list=list++[itinerary]
					times=times++[System.system_time(:milliseconds)-(query|>API.get|>elem(2))]
					API.put(conn, query, list)
					API.put({"times", query}, times)
					queries
				false->
					if API.member(query) do
						send(query|>API.get|>elem(0), :release)
					end
					Map.delete(queries, query)
			end
		else
			queries
		end
		StationConstructor.put_queries(StationConstructor, queries)
	end

	@doc """
	Starts a GenServer API process linked to the current process.

	This is often used to start the GenServer as part of a supervision tree.

	Once the server is started, the `init/1` function of the given module is
	called with args as its arguments to initialize the server.

	Creates new ETS table.

	### Parameters
	For API, required parameters passed to GenServer function are
	`GenServer.start_link(__MODULE__, :ok, name: UQC)`, specifying:

	module_name

	args

	options:
	- :name - used for name registration
	- :timeout - if present, the server is allowed to spend the given amount
	of milliseconds initializing or it will be terminated and the start function
	will return {:error, :timeout}
	- :debug - if present, the corresponding function in the :sys module is
	invoked
	- :spawn_opt - if present, its value is passed as options to the underlying
	process

	### Return values
	If the server is successfully created and initialized, this function returns
	{:ok, pid}, where pid is the PID of the server. If a process with the specified
	server name already exists, this function returns {:error, {:already_started,
	pid}} with the PID of that process.

	If the `init/1` callback fails with reason, this function returns {:error,
	reason}. Otherwise, if it returns {:stop, reason} or :ignore, the process
	is terminated and this function returns {:error, reason} or :ignore,
	respectively.
	"""
	def start_link do
		GenServer.start_link(__MODULE__, :ok, name: UQC)
	end

	@doc """
	Gets entry from ETS table.

	### Parameters
	key

	### Return values
	If the table has an entry with the given key, returns {:reply, elem(tuple,
	tuple_size(tuple)-1), state} otherwise {:reply, nil, state}.
	"""
	def get(key) do
		GenServer.call(UQC, {:get, key})
	end

	@doc """
	Inserts {key, value} pair into ETS table.

	### Parameters
	key

	value

	### Return values
	Returns {:ok}.
	"""
	def put(key, value) do
		GenServer.cast(UQC, {:put, key, value})
	end

	@doc """
	Inserts {connection, query, itineraries} triple into ETS table.

	### Parameters
	connection

	query

	itineraries

	### Return values
	Returns {:ok}.
	"""
	def put(connection, query, itineraries) do
		GenServer.cast(UQC, {:put_entry, connection, query, itineraries})
	end

	@doc """
	Deletes {key, value} pair from ETS table.

	### Parameters
	key

	### Return values
	Returns {:ok}.
	"""
	def remove(key) do
		GenServer.cast(UQC, {:remove, key})
	end

	@doc """
	Checks whether entry with given key is present in ETS table.

	### Parameters
	key

	### Return values
	Returns {:reply, true, state} or {:reply, false, state}.

	"""
	def member(key) do
		GenServer.call(UQC, {:member, key})
	end

	## Server callbacks
	def init(:ok) do
		table=:ets.new(:table, [:named_table, read_concurrency: true,
			write_concurrency: true])
		{:ok, {table}}
	end

	def handle_call({:get, key}, _from, {table}=state) do
		entry=:ets.lookup(table, key)
		if length(entry)===0 do
			{:reply, nil, state}
		else
			[tuple]=entry
			{:reply, elem(tuple, tuple_size(tuple)-1), state}
		end

	end

	def handle_call({:member, key}, _from, {table}=state) do
		{:reply, :ets.member(table, key), state}
	end

	def handle_cast({:put, key, value}, {table}) do
		:ets.insert(table, {key, value})
		{:noreply, {table}}
	end

	def handle_cast({:put_entry, connection, query, itineraries}, {table}) do
		:ets.insert(table, {connection, query, itineraries})
		{:noreply, {table}}
	end

	def handle_cast({:remove, key}, {table}) do
		:ets.delete(table, key)
		{:noreply, {table}}
	end

	def handle_info({:DOWN, :process, _pid, _reason}, {table}) do
		:ets.delete(table)
		{:noreply, {table}}
	end

	def handle_info(_msg, state) do
		{:noreply, state}
	end

	## Other functions
	defp sort_list(list) do
		Enum.sort(list, &((((List.first(&1)).day*86_400)+
			(List.last(&1)).arrival_time-(List.first(&1)).arrival_time)<
		(((List.first(&2)).day*86_400)+(List.last(&2)).arrival_time-
			(List.first(&2)).arrival_time)))
	end

	defp update_list(oldlist, newlist, val, repl, n) when n>0 do
		[elt|oldlist]=oldlist
		add_entry=if elt.vehicleID===val do
			repl
		else
			elt
		end
		newlist=newlist++[add_entry]
		update_list(oldlist, newlist, val, repl, n-1)
	end

	# Closes the file after reading data of n stations.
	defp update_list(_, newlist, _, _, _) do
		newlist
	end
end
