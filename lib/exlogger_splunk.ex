defmodule ExLogger.Backend.Splunk do
  use ExLogger.Backend

  @source_type "json_predefined_timestamp"

  defrecordp :backend_state, :backend_state,
              hostname: nil, project: nil, threshold: 1, queue_timeout: 500,
              http_auth: nil,
              queue: [], timeout_timer: nil


  def backend_init(options) do
  	http_auth = "Basic " <> ("x:#{options[:access_token]}" |> :base64.encode)
    {:ok, backend_state(hostname: options[:hostname], project: options[:project],
    	                threshold: options[:threshold] || 1, http_auth: http_auth,
    	                queue_timeout: options[:queue_timeout] || 500)}
  end

  def handle_log(message(timestamp: timestamp,
                          level: level, message: msg, object: object,
                          module: module, file: file, line: line, pid: pid),
                  backend_state(threshold: threshold, queue: queue, queue_timeout: queue_timeout,
                  	            timeout_timer: timeout_timer) = s) do
  	object = [
  		timestamp: format_timestamp(timestamp),
  		level: "#{level}",
  		message: iolist_to_binary(ExLogger.Format.format(msg, object)),
  		object: format_object(object),
  		module: inspect(module),
  		file: "#{file}:#{line}",
  		pid: format_pid(pid),
    ]
    if length(queue) + 1 == threshold do
      dequeue(backend_state(s, queue: [object|queue]))
    else
      unless nil?(timeout_timer), do: :erlang.cancel_timer(timeout_timer)
      timeout_timer = :erlang.send_after(queue_timeout, self, {__MODULE__, :dequeue})
      backend_state(s, queue: [object|queue], timeout_timer: timeout_timer)
    end
  end

  def handle_info({__MODULE__, :dequeue}, state(state: b) = s) do
  	b = dequeue(b)
  	s = state(s, state: b)
  	{:ok, s}
  end

  defp dequeue(backend_state(hostname: hostname, project: project, http_auth: http_auth,
  	                         queue: queue, queue_timeout: queue_timeout, timeout_timer: timeout_timer) = s) do
    unless nil?(timeout_timer), do: :erlang.cancel_timer(timeout_timer)
    data = Enum.reverse(queue) |> Enum.map(&JSEX.encode!(&1)) |> Enum.join("\n")
    case :hackney.request(:post, "https://#{hostname}/1/inputs/http?index=#{project}&sourcetype=" <> @source_type,
    	                  [{"Content-type","text/plain"},
    	                   {"Authorization", http_auth}], data, []) do
   	  {:ok, 200, _, client} ->
	    :hackney.close(client)
	  	backend_state(s, queue: [], timeout_timer: nil)
	  {_, _, _, client} ->
	    :hackney.close(client)
	  	timeout_timer = :erlang.send_after(queue_timeout, self, {__MODULE__, :dequeue})
        backend_state(s, timeout_timer: timeout_timer)
    end
  end

  defp format_timestamp(timestamp) do
  	{_mega, _sec, micro} = timestamp
  	milli = div(micro, 1000)
    time = :calendar.now_to_local_time(timestamp)
    {{year, month, day}, {hour, minute, second}} = time
    "#{year}-#{month}-#{day}T#{hour}:#{minute}:#{second}." <> String.rjust("#{milli}", 3, ?0)
  end

  defp format_pid(nil), do: nil
  defp format_pid(pid), do: "#{inspect pid}"

  defp format_object(list) when is_list(list) do
  	lc item inlist list, do: format_object(item)
  end
  defp format_object(reason) when is_record(reason, ExLogger.ErrorLoggerHandler.Reason) do
    inspect(reason)
  end
  defp format_object({key, value}) when is_binary(key) or is_atom(key) do
  	{key, format_object(value)}
  end
  defp format_object(tuple) when is_tuple(tuple) do
  	format_object([tuple: tuple_to_list(tuple)])
  end
  defp format_object(bool) when bool in [true, false], do: bool
  defp format_object(other) when is_pid(other) or is_port(other) or is_reference(other)
                              or is_atom(other) do
    inspect(other)
  end
  defp format_object(other), do: other

end
