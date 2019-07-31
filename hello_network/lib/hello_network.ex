defmodule HelloNetwork do
  @moduledoc """
  Example of setting up wired and wireless networking on a Nerves device.
  """

  require Logger

  alias Nerves.Network
  alias Nerves.Leds

  @interface Application.get_env(:hello_network, :interface, :eth0)

  # Durations are in milliseconds
  @on_duration 100
  @off_duration 1000
  @time_between_blinks 100

  @endpoint "https://ampeigonet.github.io/lights-endpoint/app/views/status/status.json"

  @doc "Main entry point into the program. This is an OTP callback."
  def start(_type, _args) do
    GenServer.start_link(__MODULE__, to_string(@interface), name: __MODULE__)

    :timer.sleep(40000)

    get_status()

    {:ok, self()}
  end

  @doc "Are we connected to the internet?"
  def connected?, do: GenServer.call(__MODULE__, :connected?)

  @doc "Returns the current ip address"
  def ip_addr, do: GenServer.call(__MODULE__, :ip_addr)

  @doc """
  Attempts to perform a DNS lookup to test connectivity.

  ## Examples

    iex> HelloNetwork.test_dns()
    {:ok,
     {:hostent, 'nerves-project.org', [], :inet, 4,
      [{192, 30, 252, 154}, {192, 30, 252, 153}]}}
  """
  def test_dns(hostname \\ 'nerves-project.org') do
    :inet_res.gethostbyname(hostname)
  end

  ## GenServer callbacks

  def init(interface) do
    Network.setup(interface)

    SystemRegistry.register()
    {:ok, %{interface: interface, ip_address: nil, connected: false}}
  end

  def handle_info({:system_registry, :global, registry}, state) do
    ip = get_in(registry, [:state, :network_interface, state.interface, :ipv4_address])

    if ip != state.ip_address do
      Logger.info("IP ADDRESS CHANGED: #{ip}")
    end

    connected = match?({:ok, {:hostent, 'nerves-project.org', [], :inet, 4, _}}, test_dns())
    {:noreply, %{state | ip_address: ip, connected: connected || false}}
  end

  def handle_info(_, state), do: {:noreply, state}

  def handle_call(:connected?, _from, state), do: {:reply, state.connected, state}
  def handle_call(:ip_addr, _from, state), do: {:reply, state.ip_address, state}

  def get_status do
    HTTPoison.start
    response = HTTPoison.get!(
      @endpoint,
      [],
      [ssl: [{:verify, :verify_none}]]
    )

    Logger.debug("Response body: #{inspect(response.body)}")

    json_response = Poison.decode!(response.body)

    {blinks, _} = Integer.parse(json_response["state"])
    # blinks = 3

    led_list = [:green]
    Logger.debug("list of leds to blink is #{inspect(led_list)}")
    spawn(fn -> blink_list_forever(led_list, blinks) end)
  end

  # call blink_led on each led in the list sequence, repeating forever
  defp blink_list_forever(led_list, blinks) do
    Enum.each(led_list, &blink(&1, blinks))
    blink_list_forever(led_list, blinks)
  end

  # given an led key, turn it on for @on_duration then back off
  def blink(led_key, blinks) do
    (1..blinks) |> Enum.each(fn _ ->
      Logger.debug "blinking led #{inspect led_key}"
      Leds.set([{led_key, true}])
      Logger.debug("on")
      :timer.sleep(@on_duration)
      Leds.set([{led_key, false}])
      Logger.debug("off")
      :timer.sleep(@time_between_blinks)
    end)
    Logger.debug("-----")
    :timer.sleep(@off_duration)
  end
end
