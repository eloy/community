defmodule Community.Driver do
  @callback handle_community(Any.t, Any.t) :: any
  @callback start_service(Any.t, Any.t) :: any
end
