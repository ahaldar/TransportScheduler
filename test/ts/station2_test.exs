# Module to test Station2
# Successfully creates new station process with associated FSM and updates local variable values

defmodule Station2Test do
  use ExUnit.Case 
  
  test "station" do
    
    # Start the server
    {:ok, station} = GenStateMachine.start_link(Station2, {:nodata, nil})

    # This is the client
    Station2.update(station,  %{:delay => 0.38, :congestion => "high", :disturbance => "no"})
    assert GenStateMachine.call(station, :get_vars).delay == 0.38 * 3.0
    
    Station2.update(station, %{:delay => 0.38, :congestion => "none", :disturbance => "yes"}) 
    assert GenStateMachine.call(station, :get_state) == :disturbance
  end
end
