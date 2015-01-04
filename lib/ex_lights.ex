defmodule Lights do

  @controller "http://192.168.1.193/arduino"

  def today_at(hr, min, fct) do
    at_time_with_delay(hr, min, fct)
  end

  def tomorrow_at(hr, min, fct) do
    one_day_sec = 24*60*60
    at_time_with_delay(hr, min, fct, one_day_sec)
  end

  def at_time_with_delay(hr, min, fct, delay \\ 0) do
    {date, _} = :calendar.local_time()
    datetime = {date, {hr, min, 0}}
    sec = &:calendar.datetime_to_gregorian_seconds/1
    sec_diff = sec.(datetime) - sec.(:calendar.local_time()) + delay
    case sec_diff do
      x when x > 0 ->
        :timer.send_after 1000 * sec_diff, self(), {:now, fct}
      _ ->
        spawn fct
    end
  end

  def timer_process do
    receive do
      :shutdown ->
        exit(:shutdown)
      {:today, hr, min, f} ->
        today_at(hr, min, f)
      {:tomorrow, hr, min, f} ->
        tomorrow_at(hr, min, f)
      {:now, f} ->
        spawn f
      x -> IO.puts "timer #{inspect x}"
    end
    timer_process
  end

  def comm_process do
    HTTPotion.start
    comm_loop
  end

  def comm_loop do
    receive do
      :shutdown ->
        exit(:shutdown)
      {:digital_write, pin, value} ->
        HTTPotion.get "#{@controller}/digital/#{pin}/#{value}"
      x -> IO.puts "comm #{inspect x}"
    end
    comm_loop
  end

  def main_loop do
    receive do
      {:timer, t, f} ->
        send :lights_timer, {t, f}
      {:mode, pin, mode} ->
        send :lights_comm, {:mode, pin, mode}
      {:read, pin} ->
        send :lights_comm, {:read, pin, self()}
      {:digital_write, pin, value} ->
        send :lights_comm, {:digital_write, pin, value}
      {:reply, msg} ->
        IO.puts msg
      :shutdown ->
        send :lights_comm, :shutdown
        send :lights_timer, :shutdown
        exit(:shutdown)
    end
    main_loop
  end

  def lights_fn do
    send :timer, {:today, 8, 0, fn -> send :main, {:digital_write, 7, 1} end}
    send :timer, {:today, 20, 0, fn -> send :main, {:digital_write, 7, 0} end}
    send :timer, {:tomorrow, 0, 1, &lights_fn/0}
  end

  def init do
    timer = spawn &timer_process/0
    Process.register(timer, :lights_timer)

    comm = spawn &comm_process/0
    Process.register(comm, :lights_comm)

    main = spawn &main_loop/0
    Process.register(main, :lights)

    send :lights_timer, {:tomorrow, 0, 1, &lights_fn/0}
  end
end
