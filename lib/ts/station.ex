# Module to create station FSM, fails to link FSM with process
# Use station2.ex module instead

defmodule Station do
  use Fsm, initial_state: :nodata, initial_data: nil
  
  @doc """
  Starts a transport station.
  """
  def start_link do
    Agent.start_link(fn -> %{} end)
  end

  defstate nodata do
  end

  defstate disturbance do
  end

  defstate delay do
  end
  
  # Global event handler
  defevent update(values) do
    
    case(values.disturbance) do
      "yes"	-> next_state(:disturbance, nil)
      "no"	-> 
	case(values.congestion) do
	  "none"	->
	    next_state(:delay, values)
	  "low"		->
	    newValues = %{values | :delay => Map.get(values, :delay) * 2}
	    next_state(:delay, newValues)
	  "high"	->
	    newValues = %{values | :delay => Map.get(values, :delay) * 3}
	    next_state(:delay, newValues)
	  _				->
	    next_state(:delay, values)	
	end
      _			-> next_state(:delay, values)	
    end          

  end
end


