defmodule ExLogger.Backend.Splunk.TCP do
  use ExLogger.Backend

  defrecordp :backend_state, :backend_state,
              hostname: nil, port: nil, socket: nil


  def backend_init(options) do
    socket = Socket.TCP.connect!(options[:hostname], options[:port])
    {:ok, backend_state(hostname: options[:hostname], port: options[:port],
                        socket: socket)}
  end

  def handle_log(message(timestamp: timestamp,
                          level: level, message: msg, object: object,
                          module: module, file: file, line: line, pid: pid),
                  backend_state(socket: socket) = s) do
  	object = [
  		timestamp: format_timestamp(timestamp),
  		level: "#{level}",
  		message: iolist_to_binary(ExLogger.Format.format(msg, object)),
  		object: format_object(object),
  		module: inspect(module),
  		file: "#{file}:#{line}",
  		pid: format_pid(pid),
    ]
    Socket.Stream.send!(socket, JSEX.encode!(object) <> "\n")
    s
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
