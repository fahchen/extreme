defmodule ExtremeTest do
  use ExUnit.Case, async: false
  alias Extreme.Msg, as: ExMsg
  require Logger

  defmodule(PersonCreated, do: defstruct([:name]))
  defmodule(PersonChangedName, do: defstruct([:name]))

  setup do
    {:ok, server} =
      Application.get_env(:extreme, :event_store)
      |> Extreme.start_link()

    {:ok, server: server}
  end

  ## Authentication

  test ".execute is not authenticated for wrong credentials" do
    {:ok, server} =
      Application.get_env(:extreme, :event_store)
      |> Keyword.put(:password, "wrong")
      |> Extreme.start_link()

    assert {:error, :not_authenticated} = Extreme.execute(server, _write_events())
  end

  ## Writing events

  test "writing events is success for non existing stream", %{server: server} do
    Logger.debug("TEST: writing events is success for non existing stream")

    assert {:ok, %{result: :Success} = response} =
             Extreme.execute(server, _write_events(_random_stream_name()))

    Logger.debug("Write response: #{inspect(response)}")
  end

  test "writing events is success for existing stream", %{server: server} do
    Logger.debug("TEST: writing events is success for existing stream")
    stream = _random_stream_name()
    assert {:ok, %{result: :Success} = response} = Extreme.execute(server, _write_events(stream))
    Logger.debug("First write response: #{inspect(response)}")
    assert {:ok, %{result: :Success} = response} = Extreme.execute(server, _write_events(stream))
    Logger.debug("Second write response: #{inspect(response)}")
  end

  test "writing events is success for soft deleted stream", %{server: server} do
    Logger.debug("TEST: writing events is success for soft deleted stream")
    stream = _random_stream_name()
    assert {:ok, %{result: :Success} = response} = Extreme.execute(server, _write_events(stream))
    Logger.debug("First write response: #{inspect(response)}")

    assert {:ok, %{result: :Success} = response} =
             Extreme.execute(server, _delete_stream(stream, false))

    Logger.debug("Deletion response: #{inspect(response)}")
    assert {:ok, %{result: :Success} = response} = Extreme.execute(server, _write_events(stream))
    Logger.debug("Second write response: #{inspect(response)}")
  end

  test "writing events is NOT success for hard deleted stream", %{server: server} do
    Logger.debug("TEST: writing events is NOT success for hard deleted stream")
    stream = _random_stream_name()
    assert {:ok, %{result: :Success} = response} = Extreme.execute(server, _write_events(stream))
    Logger.debug("First write response: #{inspect(response)}")

    assert {:ok, %{result: :Success} = response} =
             Extreme.execute(server, _delete_stream(stream, true))

    Logger.debug("Deletion response: #{inspect(response)}")
    assert {:error, :StreamDeleted, response} = Extreme.execute(server, _write_events(stream))
    Logger.debug("Second write response: #{inspect(response)}")
  end

  ## Reading events:

  test "reading events is success even when response data is received in more tcp packages", %{
    server: server
  } do
    Logger.debug(
      "TEST: reading events is success even when response data is received in more tcp packages"
    )

    stream = _random_stream_name()

    events = [
      %PersonCreated{name: "Reading"},
      %PersonChangedName{name: "Reading Test"},
      %PersonChangedName{name: "Reading Test"},
      %PersonChangedName{name: "Reading Test"},
      %PersonChangedName{name: "Reading Test"},
      %PersonChangedName{name: "Reading Test"},
      %PersonChangedName{name: "Reading Test"},
      %PersonChangedName{name: "Reading Test"},
      %PersonChangedName{name: "Reading Test"},
      %PersonChangedName{name: "Reading Test"},
      %PersonChangedName{name: "Reading Test"},
      %PersonChangedName{name: "Reading Test"},
      %PersonChangedName{name: "Reading Test"},
      %PersonChangedName{name: "Reading Test"},
      %PersonChangedName{name: "Reading Test"},
      %PersonChangedName{name: "Reading Test"},
      %PersonChangedName{name: "Reading Test"},
      %PersonChangedName{name: "Reading Test"},
      %PersonChangedName{name: "Reading Test"}
    ]

    {:ok, _} = Extreme.execute(server, _write_events(stream, events))
    {:ok, response} = Extreme.execute(server, _read_events(stream))

    assert events ==
             Enum.map(response.events, fn event -> :erlang.binary_to_term(event.event.data) end)
  end

  test "reading events from non existing stream returns :NoStream", %{server: server} do
    Logger.debug("TEST: reading events from non existing stream returns :NoStream")

    {:error, :NoStream, _es_response} =
      Extreme.execute(server, _read_events(_random_stream_name()))
  end

  test "reading events from soft deleted stream returns :NoStream", %{server: server} do
    Logger.debug("TEST: reading events from soft deleted stream returns :NoStream")
    stream = _random_stream_name()
    {:ok, _} = Extreme.execute(server, _write_events(stream))
    {:ok, _} = Extreme.execute(server, _delete_stream(stream, false))
    {:error, :NoStream, _es_response} = Extreme.execute(server, _read_events(stream))
  end

  test "reading events from hard deleted stream returns :NoStream", %{server: server} do
    Logger.debug("TEST: reading events from hard deleted stream returns :StreamDeleted")
    stream = _random_stream_name()
    {:ok, _} = Extreme.execute(server, _write_events(stream))
    {:ok, _} = Extreme.execute(server, _delete_stream(stream, true))
    {:error, :StreamDeleted, _es_response} = Extreme.execute(server, _read_events(stream))
  end

  test "reading last event is success", %{server: server} do
    Logger.debug("TEST: reading last event is success")
    stream = _random_stream_name()

    events =
      [_, event2] = [%PersonCreated{name: "Reading"}, %PersonChangedName{name: "Reading Test"}]

    {:ok, _} = Extreme.execute(server, _write_events(stream, events))
    {:ok, response} = Extreme.execute(server, _read_events_backward(stream))

    assert %{is_end_of_stream: false, last_event_number: 1, next_event_number: 0} = response
    assert [ev2] = response.events
    assert event2 == :erlang.binary_to_term(ev2.event.data)
    assert ev2.event.event_number == 1
  end

  test "reading events backward is success", %{server: server} do
    Logger.debug("TEST: reading events backward is success")
    stream = _random_stream_name()

    events =
      [event1, event2] = [
        %PersonCreated{name: "Reading"},
        %PersonChangedName{name: "Reading Test"}
      ]

    {:ok, _} = Extreme.execute(server, _write_events(stream, events))
    {:ok, response} = Extreme.execute(server, _read_events_backward(stream, -1, 4096))

    assert %{is_end_of_stream: true, last_event_number: 1, next_event_number: -1} = response
    assert [ev2, ev1] = response.events
    assert event2 == :erlang.binary_to_term(ev2.event.data)
    assert event1 == :erlang.binary_to_term(ev1.event.data)
    assert ev2.event.event_number == 1
    assert ev1.event.event_number == 0
  end

  ## Subscriber test helper process

  defmodule Subscriber do
    use GenServer

    def start_link(sender) do
      GenServer.start_link(__MODULE__, sender, name: __MODULE__)
    end

    def received_events(server) do
      GenServer.call(server, :received_events)
    end

    def init(sender) do
      {:ok, %{sender: sender, received: []}}
    end

    def handle_info({:on_event, event} = message, state) do
      send(state.sender, message)
      {:noreply, %{state | received: [event | state.received]}}
    end

    def handle_info({:on_event, event, _correlation_id} = message, state) do
      send(state.sender, message)
      {:noreply, %{state | received: [event | state.received]}}
    end

    def handle_info({:extreme, _, problem, stream} = message, state) do
      Logger.warn("Stream #{stream} issue: #{to_string(problem)}")
      send(state.sender, message)
      {:noreply, state}
    end

    def handle_info(:caught_up, state) do
      send(state.sender, :caught_up)
      {:noreply, state}
    end

    def handle_call(:received_events, _from, state) do
      result =
        state.received
        |> Enum.reverse()
        |> Enum.map(fn e ->
          data = e.event.data
          :erlang.binary_to_term(data)
        end)

      {:reply, result, state}
    end
  end

  ## Subscribing to stream

  test "subscribe to existing stream is success", %{server: server} do
    Logger.debug("TEST: subscribe to existing stream is success")
    stream = _random_stream_name()
    # prepopulate stream
    events1 = [%PersonCreated{name: "1"}, %PersonCreated{name: "2"}, %PersonCreated{name: "3"}]
    {:ok, _} = Extreme.execute(server, _write_events(stream, events1))

    # subscribe to existing stream
    {:ok, subscriber} = Subscriber.start_link(self())
    {:ok, subscription} = Extreme.subscribe_to(server, subscriber, stream)
    Logger.debug(inspect(subscription))

    # :caught_up is not received on subscription without previous read
    refute_receive :caught_up

    # write two more events after subscription
    events2 = [%PersonCreated{name: "4"}, %PersonCreated{name: "5"}]
    {:ok, _} = Extreme.execute(server, _write_events(stream, events2))

    # assert rest events have arrived
    assert_receive {:on_event, _event}
    assert_receive {:on_event, _event}

    # check if only new events came in correct order.
    assert Subscriber.received_events(subscriber) == events2
  end

  test "subscribe to non existing stream is success", %{server: server} do
    Logger.debug("TEST: subscribe to non existing stream is success")
    # subscribe to stream
    stream = _random_stream_name()
    {:error, :NoStream, _es_response} = Extreme.execute(server, _read_events(stream))
    {:ok, subscriber} = Subscriber.start_link(self())
    {:ok, subscription} = Extreme.subscribe_to(server, subscriber, stream)
    Logger.debug(inspect(subscription))

    # write two events after subscription
    events = [%PersonCreated{name: "1"}, %PersonCreated{name: "2"}]
    {:ok, _} = Extreme.execute(server, _write_events(stream, events))

    # assert rest events have arrived
    assert_receive {:on_event, _event}
    assert_receive {:on_event, _event}

    # check if only new events came in correct order.
    assert Subscriber.received_events(subscriber) == events
  end

  test "subscribe to soft deleted stream is success", %{server: server} do
    Logger.debug("TEST: subscribe to soft deleted stream is success")
    stream = _random_stream_name()
    # prepopulate stream
    events1 = [%PersonCreated{name: "1"}, %PersonCreated{name: "2"}, %PersonCreated{name: "3"}]
    {:ok, _} = Extreme.execute(server, _write_events(stream, events1))
    {:ok, _} = Extreme.execute(server, _delete_stream(stream, false))
    {:error, :NoStream, _es_response} = Extreme.execute(server, _read_events(stream))

    # subscribe to stream
    {:ok, subscriber} = Subscriber.start_link(self())
    {:ok, subscription} = Extreme.subscribe_to(server, subscriber, stream)
    Logger.debug(inspect(subscription))

    # write two more events after subscription
    events2 = [%PersonCreated{name: "4"}, %PersonCreated{name: "5"}]
    {:ok, _} = Extreme.execute(server, _write_events(stream, events2))

    # assert rest events have arrived
    assert_receive {:on_event, _event}
    assert_receive {:on_event, _event}

    # check if only new events came in correct order.
    assert Subscriber.received_events(subscriber) == events2
  end

  ## Subscribe to hard deleted stream is ok as per EventStore!?
  # test "subscribe to hard deleted stream is NOT success", %{server: server} do
  #  stream = _random_stream_name()
  #  # prepopulate stream
  #  events1 = [%PersonCreated{name: "1"}, %PersonCreated{name: "2"}, %PersonCreated{name: "3"}]
  #  {:ok, _} = Extreme.execute(server, _write_events(stream, events1))
  #  {:ok, _} = Extreme.execute(server, _delete_stream(stream, true))
  #  {:error, :StreamDeleted, _es_response} = Extreme.execute(server, _read_events(stream))

  #  # subscribe to stream
  #  {:ok, subscriber} = Subscriber.start_link(self())
  #  {:ok, _subscription} = Extreme.subscribe_to(server, subscriber, stream)

  #  assert_receive {:extreme, :error, :stream_hard_deleted, ^stream}
  # end

  ## Read and Stay subscribed

  test "read events and stay subscribed for existing stream is ok", %{server: server} do
    {:ok, server2} =
      Application.get_env(:extreme, :event_store)
      |> Extreme.start_link(name: SubscriptionConnection)

    Logger.debug("SELF: #{inspect(self())}")
    Logger.debug("Connection 1: #{inspect(server)}")
    Logger.debug("Connection 2: #{inspect(server2)}")
    stream = _random_stream_name()
    # prepopulate stream
    events1 = [%PersonCreated{name: "1"}, %PersonCreated{name: "2"}, %PersonCreated{name: "3"}]
    {:ok, _} = Extreme.execute(server, _write_events(stream, events1))

    # subscribe to existing stream
    {:ok, subscriber} = Subscriber.start_link(self())
    {:ok, _subscription} = Extreme.read_and_stay_subscribed(server, subscriber, stream, 0, 2)

    # assert first 3 events are received
    assert_receive {:on_event, _event}
    assert_receive {:on_event, _event}
    assert_receive {:on_event, _event}

    # assert :caught_up is received when existing events are read
    assert_receive :caught_up

    # write two more after subscription
    events2 = [
      %PersonCreated{name: "4"},
      %PersonCreated{name: "5"},
      %PersonCreated{name: "6"},
      %PersonCreated{name: "7"},
      %PersonCreated{name: "8"},
      %PersonCreated{name: "9"},
      %PersonCreated{name: "10"},
      %PersonCreated{name: "11"},
      %PersonCreated{name: "12"},
      %PersonCreated{name: "13"},
      %PersonCreated{name: "14"},
      %PersonCreated{name: "15"},
      %PersonCreated{name: "16"},
      %PersonCreated{name: "17"},
      %PersonCreated{name: "18"},
      %PersonCreated{name: "19"},
      %PersonCreated{name: "20"},
      %PersonCreated{name: "21"},
      %PersonCreated{name: "22"},
      %PersonCreated{name: "23"},
      %PersonCreated{name: "24"},
      %PersonCreated{name: "25"},
      %PersonCreated{name: "26"},
      %PersonCreated{name: "27"}
    ]

    {:ok, _} = Extreme.execute(server, _write_events(stream, events2))

    # assert rest events have arrived as well
    assert_receive {:on_event, _event}
    assert_receive {:on_event, _event}
    assert_receive {:on_event, _event}
    assert_receive {:on_event, _event}
    assert_receive {:on_event, _event}
    assert_receive {:on_event, _event}
    assert_receive {:on_event, _event}
    assert_receive {:on_event, _event}
    assert_receive {:on_event, _event}
    assert_receive {:on_event, _event}
    assert_receive {:on_event, _event}
    assert_receive {:on_event, _event}
    assert_receive {:on_event, _event}
    assert_receive {:on_event, _event}
    assert_receive {:on_event, _event}
    assert_receive {:on_event, _event}
    assert_receive {:on_event, _event}
    assert_receive {:on_event, _event}
    assert_receive {:on_event, _event}
    assert_receive {:on_event, _event}
    assert_receive {:on_event, _event}
    assert_receive {:on_event, _event}
    assert_receive {:on_event, _event}
    assert_receive {:on_event, _event}

    ## check if they came in correct order.
    assert Subscriber.received_events(subscriber) == events1 ++ events2

    {:ok, response} = Extreme.execute(server, _read_events(stream))

    assert events1 ++ events2 ==
             Enum.map(response.events, fn event -> :erlang.binary_to_term(event.event.data) end)
  end

  test "read events and stay subscribed for never existed stream is ok", %{server: server} do
    # subscribe to stream
    stream = _random_stream_name()
    {:error, :NoStream, _} = Extreme.execute(server, _read_events(stream))
    {:ok, subscriber} = Subscriber.start_link(self())
    {:ok, _subscription} = Extreme.read_and_stay_subscribed(server, subscriber, stream, 0, 2)

    # assert :caught_up is received when existing events are read
    assert_receive :caught_up

    # write two events after subscription
    events = [%PersonCreated{name: "1"}, %PersonCreated{name: "2"}]
    {:ok, _} = Extreme.execute(server, _write_events(stream, events))

    # assert rest events have arrived as well
    assert_receive {:on_event, _event}
    assert_receive {:on_event, _event}

    # check if they came in correct order.
    assert Subscriber.received_events(subscriber) == events

    {:ok, response} = Extreme.execute(server, _read_events(stream))

    assert events ==
             Enum.map(response.events, fn event -> :erlang.binary_to_term(event.event.data) end)
  end

  test "read events and stay subscribed for soft deleted stream is ok", %{server: server} do
    # soft delete stream
    stream = _random_stream_name()
    events = [%PersonCreated{name: "1"}, %PersonCreated{name: "2"}]
    {:ok, _} = Extreme.execute(server, _write_events(stream, events))
    {:ok, _} = Extreme.execute(server, _read_events(stream))
    {:ok, _} = Extreme.execute(server, _delete_stream(stream, false))

    # subscribe to stream
    {:ok, subscriber} = Subscriber.start_link(self())
    {:ok, _subscription} = Extreme.read_and_stay_subscribed(server, subscriber, stream, 0, 2)

    # assert :caught_up is received when existing events are read
    assert_receive :caught_up

    # write two events after subscription
    events = [%PersonCreated{name: "1"}, %PersonCreated{name: "2"}]
    {:ok, _} = Extreme.execute(server, _write_events(stream, events))

    # assert rest events have arrived as well
    assert_receive {:on_event, _event}
    assert_receive {:on_event, _event}

    # check if they came in correct order.
    assert Subscriber.received_events(subscriber) == events

    {:ok, response} = Extreme.execute(server, _read_events(stream))

    assert events ==
             Enum.map(response.events, fn event -> :erlang.binary_to_term(event.event.data) end)
  end

  test "read events and stay subscribed for hard deleted stream is not ok", %{server: server} do
    # hard delete stream
    stream = _random_stream_name()
    events = [%PersonCreated{name: "1"}, %PersonCreated{name: "2"}]
    {:ok, _} = Extreme.execute(server, _write_events(stream, events))
    {:ok, _} = Extreme.execute(server, _read_events(stream))
    {:ok, _} = Extreme.execute(server, _delete_stream(stream, true))

    # subscribe to stream
    {:ok, subscriber} = Subscriber.start_link(self())
    {:ok, _subscription} = Extreme.read_and_stay_subscribed(server, subscriber, stream, 0, 2)

    # assert error is sent to receiver
    assert_receive {:extreme, :error, :stream_hard_deleted, ^stream}
  end

  test "reading single existing event is success", %{server: server} do
    stream = _random_stream_name()
    events = [%PersonCreated{name: "Reading"}, %PersonChangedName{name: "Reading Test"}]
    expected_event = List.last(events)

    {:ok, _} = Extreme.execute(server, _write_events(stream, events))
    assert {:ok, response} = Extreme.execute(server, _read_event(stream, 1))
    assert expected_event == :erlang.binary_to_term(response.event.event.data)
  end

  test "trying to read non existing event from existing stream returns :NotFound", %{
    server: server
  } do
    stream = _random_stream_name()
    events = [%PersonCreated{name: "Reading"}, %PersonChangedName{name: "Reading Test"}]
    expected_event = List.last(events)

    {:ok, _} = Extreme.execute(server, _write_events(stream, events))
    assert {:ok, response} = Extreme.execute(server, _read_event(stream, 1))
    assert expected_event == :erlang.binary_to_term(response.event.event.data)

    assert {:error, :NotFound, _read_event_completed} =
             Extreme.execute(server, _read_event(stream, 2))
  end

  test "soft deleting stream can be done multiple times", %{server: server} do
    stream = _random_stream_name()
    events = [%PersonCreated{name: "Reading"}]
    {:ok, _} = Extreme.execute(server, _write_events(stream, events))
    assert {:ok, _response} = Extreme.execute(server, _read_events(stream))

    {:ok, _} = Extreme.execute(server, _delete_stream(stream))
    assert {:error, :NoStream, _es_response} = Extreme.execute(server, _read_events(stream))

    {:ok, _} = Extreme.execute(server, _write_events(stream, events))
    assert {:ok, _response} = Extreme.execute(server, _read_events(stream))
    {:ok, _} = Extreme.execute(server, _delete_stream(stream))
    assert {:error, :NoStream, _es_response} = Extreme.execute(server, _read_events(stream))
  end

  test "hard deleted stream can be done only once", %{server: server} do
    stream = _random_stream_name()
    events = [%PersonCreated{name: "Reading"}]
    {:ok, _} = Extreme.execute(server, _write_events(stream, events))
    assert {:ok, _response} = Extreme.execute(server, _read_events(stream))

    {:ok, _} = Extreme.execute(server, _delete_stream(stream, true))
    assert {:error, :StreamDeleted, _es_response} = Extreme.execute(server, _read_events(stream))
    {:error, :StreamDeleted, _} = Extreme.execute(server, _write_events(stream, events))
  end

  @tag :benchmark
  test "it writes 1_000 events in less then 2 seconds", %{server: server} do
    Logger.debug("TEST: it writes 1_000 events in less then 2 seconds")
    stream = _random_stream_name()

    fun = fn ->
      for(_ <- 0..499, do: Extreme.execute(server, _write_events(stream)))
    end

    time =
      fun
      |> :timer.tc()
      |> elem(0)

    Logger.info("!!! Execution time: #{inspect(time)} !!!")
    assert time < 2_100_000
  end

  describe "persistent subscription" do
    test "create on existing stream is success", %{server: server} do
      stream = "persistent-subscription-#{UUID.uuid4()}"
      events = [%PersonCreated{name: "1"}, %PersonCreated{name: "2"}, %PersonCreated{name: "3"}]

      {:ok, _} = Extreme.execute(server, _write_events(stream, events))

      assert {:ok, response} =
               Extreme.execute(
                 server,
                 _create_persistent_subscription("subscription-#{UUID.uuid4()}", stream)
               )

      assert response == %Extreme.Msg.CreatePersistentSubscriptionCompleted{
               reason: "",
               result: :Success
             }
    end

    test "recreate an existing subscription returns an already exists error", %{server: server} do
      stream = "persistent-subscription-#{UUID.uuid4()}"
      group = "subscription-#{UUID.uuid4()}"
      events = [%PersonCreated{name: "1"}, %PersonCreated{name: "2"}, %PersonCreated{name: "3"}]

      {:ok, _} = Extreme.execute(server, _write_events(stream, events))

      assert {:ok, response} =
               Extreme.execute(server, _create_persistent_subscription(group, stream))

      assert response == %Extreme.Msg.CreatePersistentSubscriptionCompleted{
               reason: "",
               result: :Success
             }

      assert {:error, :AlreadyExists, response} =
               Extreme.execute(server, _create_persistent_subscription(group, stream))

      assert response == %Extreme.Msg.CreatePersistentSubscriptionCompleted{
               reason: "Group '#{group}' already exists.",
               result: :AlreadyExists
             }
    end

    test "connect to existing persistent subscription on stream", %{server: server} do
      stream = "persistent-subscription-#{UUID.uuid4()}"
      group = "subscription-#{UUID.uuid4()}"
      buffer_size = 1

      # create persistent subscription
      {:ok, _} = Extreme.execute(server, _create_persistent_subscription(group, stream))

      # subscribe to persistent subscription
      {:ok, subscriber} = Subscriber.start_link(self())

      {:ok, subscription} =
        Extreme.connect_to_persistent_subscription(server, subscriber, group, stream, buffer_size)

      events = [%PersonCreated{name: "1"}, %PersonCreated{name: "2"}, %PersonCreated{name: "3"}]
      {:ok, _} = Extreme.execute(server, _write_events(stream, events))

      # assert events are received
      assert_receive {:on_event, event, correlation_id}
      assert :erlang.binary_to_term(event.event.data) == %PersonCreated{name: "1"}
      :ok = Extreme.PersistentSubscription.ack(subscription, event, correlation_id)

      assert_receive {:on_event, event, correlation_id}
      assert :erlang.binary_to_term(event.event.data) == %PersonCreated{name: "2"}
      :ok = Extreme.PersistentSubscription.ack(subscription, event, correlation_id)

      assert_receive {:on_event, event, correlation_id}
      assert :erlang.binary_to_term(event.event.data) == %PersonCreated{name: "3"}
      :ok = Extreme.PersistentSubscription.ack(subscription, event, correlation_id)

      # assert events came in expected order
      assert Subscriber.received_events(subscriber) == events
    end

    test "ack received event by id", %{server: server} do
      stream = "persistent-subscription-#{UUID.uuid4()}"
      group = "subscription-#{UUID.uuid4()}"
      buffer_size = 1

      # create persistent subscription
      {:ok, _} = Extreme.execute(server, _create_persistent_subscription(group, stream))

      # subscribe to persistent subscription
      {:ok, subscriber} = Subscriber.start_link(self())

      {:ok, subscription} =
        Extreme.connect_to_persistent_subscription(server, subscriber, group, stream, buffer_size)

      events = [%PersonCreated{name: "1"}, %PersonCreated{name: "2"}, %PersonCreated{name: "3"}]
      {:ok, _} = Extreme.execute(server, _write_events(stream, events))

      # assert events are received
      assert_receive {:on_event, event, correlation_id}
      assert :erlang.binary_to_term(event.event.data) == %PersonCreated{name: "1"}
      :ok = Extreme.PersistentSubscription.ack(subscription, event.event.event_id, correlation_id)

      assert_receive {:on_event, event, correlation_id}
      assert :erlang.binary_to_term(event.event.data) == %PersonCreated{name: "2"}
      :ok = Extreme.PersistentSubscription.ack(subscription, event.event.event_id, correlation_id)

      assert_receive {:on_event, event, correlation_id}
      assert :erlang.binary_to_term(event.event.data) == %PersonCreated{name: "3"}
      :ok = Extreme.PersistentSubscription.ack(subscription, event.event.event_id, correlation_id)

      # assert events came in expected order
      assert Subscriber.received_events(subscriber) == events
    end

    test "connect to existing persistent subscription on category stream", %{server: server} do
      stream_prefix = "persistent#{String.replace(UUID.uuid4(), "-", "")}"
      stream = stream_prefix <> "-subscription"
      category_stream = "$ce-" <> stream_prefix
      group = "subscription-#{UUID.uuid4()}"
      buffer_size = 1

      # create persistent subscription with resolved links to events
      {:ok, _} =
        Extreme.execute(server, _create_persistent_subscription(group, category_stream, true))

      # subscribe to persistent subscription
      {:ok, subscriber} = Subscriber.start_link(self())

      {:ok, subscription} =
        Extreme.connect_to_persistent_subscription(
          server,
          subscriber,
          group,
          category_stream,
          buffer_size
        )

      events = [%PersonCreated{name: "1"}, %PersonCreated{name: "2"}, %PersonCreated{name: "3"}]
      {:ok, _} = Extreme.execute(server, _write_events(stream, events))

      # assert events are received
      assert_receive {:on_event, event, correlation_id}
      assert :erlang.binary_to_term(event.event.data) == %PersonCreated{name: "1"}
      :ok = Extreme.PersistentSubscription.ack(subscription, event, correlation_id)

      assert_receive {:on_event, event, correlation_id}
      assert :erlang.binary_to_term(event.event.data) == %PersonCreated{name: "2"}
      :ok = Extreme.PersistentSubscription.ack(subscription, event, correlation_id)

      assert_receive {:on_event, event, correlation_id}
      assert :erlang.binary_to_term(event.event.data) == %PersonCreated{name: "3"}
      :ok = Extreme.PersistentSubscription.ack(subscription, event, correlation_id)

      # assert events came in expected order
      assert Subscriber.received_events(subscriber) == events
    end

    test "resume connection to existing persistent subscription should skip ack'd events", %{
      server: server
    } do
      stream = "persistent-subscription-#{UUID.uuid4()}"
      group = "subscription-#{UUID.uuid4()}"
      buffer_size = 1

      # create persistent subscription
      {:ok, _} = Extreme.execute(server, _create_persistent_subscription(group, stream))

      # subscribe to persistent subscription
      {:ok, subscriber} = Subscriber.start_link(self())

      {:ok, subscription} =
        Extreme.connect_to_persistent_subscription(server, subscriber, group, stream, buffer_size)

      events = [%PersonCreated{name: "1"}, %PersonCreated{name: "2"}, %PersonCreated{name: "3"}]
      {:ok, _} = Extreme.execute(server, _write_events(stream, events))

      # receive and ack first event only
      assert_receive {:on_event, event, correlation_id}
      assert :erlang.binary_to_term(event.event.data) == %PersonCreated{name: "1"}
      :ok = Extreme.PersistentSubscription.ack(subscription, event, correlation_id)

      subscriber_ref = Process.monitor(subscriber)
      subscription_ref = Process.monitor(subscription)

      # shutdown subscriber to terminate persistent subscription and its connection
      _shutdown(subscriber)

      assert_receive {:DOWN, ^subscriber_ref, _, _, _}
      refute Process.alive?(subscriber)

      assert_receive {:DOWN, ^subscription_ref, _, _, _}
      refute Process.alive?(subscription)

      # wait for event store connection to close, prevents subscriber max count reached error
      :timer.sleep(1_000)

      {:ok, subscriber} = Subscriber.start_link(self())

      {:ok, subscription} =
        Extreme.connect_to_persistent_subscription(server, subscriber, group, stream, buffer_size)

      # resumed persistent subscription should receive second and third events only
      assert_receive {:on_event, event, correlation_id}
      assert :erlang.binary_to_term(event.event.data) == %PersonCreated{name: "2"}
      :ok = Extreme.PersistentSubscription.ack(subscription, event, correlation_id)

      assert_receive {:on_event, event, correlation_id}
      assert :erlang.binary_to_term(event.event.data) == %PersonCreated{name: "3"}
      :ok = Extreme.PersistentSubscription.ack(subscription, event, correlation_id)
    end

    defmodule TestPersist do
      use GenServer

      def start_link(server, sender, group, stream) do
        GenServer.start_link(__MODULE__, {:ok, server, sender, group, stream})
      end

      def init({:ok, server, sender, group, stream}) do
        {:ok, subscription} =
          Extreme.connect_to_persistent_subscription(server, self(), group, stream, 2)

        {:ok, %{subscription: subscription, sender: sender}}
      end

      def handle_info({:on_event, event, correlation_id}, %{subscription: subscription} = state) do
        :ok = Extreme.PersistentSubscription.ack(subscription, event, correlation_id)
        send(state.sender, {:on_event, event})
        {:noreply, state}
      end
    end

    test "Quickly process events on persistent subscription", %{server: server} do
      stream = "persistent-subscription-#{UUID.uuid4()}"
      group = "subscription-#{UUID.uuid4()}"

      events = [
        %PersonCreated{name: "1"},
        %PersonCreated{name: "2"},
        %PersonCreated{name: "3"},
        %PersonCreated{name: "4"},
        %PersonCreated{name: "5"}
      ]

      {:ok, _} = Extreme.execute(server, _write_events(stream, events))

      assert {:ok, response} =
               Extreme.execute(server, _create_persistent_subscription(group, stream))

      assert response == %Extreme.Msg.CreatePersistentSubscriptionCompleted{
               reason: "",
               result: :Success
             }

      TestPersist.start_link(server, self(), group, stream)

      assert_receive {:on_event, event}
      assert :erlang.binary_to_term(event.event.data) == %PersonCreated{name: "1"}
      assert_receive {:on_event, event}
      assert :erlang.binary_to_term(event.event.data) == %PersonCreated{name: "2"}
      assert_receive {:on_event, event}
      assert :erlang.binary_to_term(event.event.data) == %PersonCreated{name: "3"}
      assert_receive {:on_event, event}
      assert :erlang.binary_to_term(event.event.data) == %PersonCreated{name: "4"}
      assert_receive {:on_event, event}
      assert :erlang.binary_to_term(event.event.data) == %PersonCreated{name: "5"}

      assert {:ok, response} =
               Extreme.execute(server, delete_persistent_subscription(group, stream))

      assert response == %Extreme.Msg.DeletePersistentSubscriptionCompleted{
               reason: "",
               result: :Success
             }
    end

    defmodule TestPersistRetry do
      use GenServer

      def start_link(server, sender, group, stream) do
        GenServer.start_link(__MODULE__, {:ok, server, sender, group, stream})
      end

      def init({:ok, server, sender, group, stream}) do
        {:ok, subscription} =
          Extreme.connect_to_persistent_subscription(server, self(), group, stream, 1)

        {:ok, %{subscription: subscription, sender: sender, retry_count: 0}}
      end

      def handle_info(
            {:on_event, event, correlation_id},
            %{retry_count: retry_count, subscription: subscription} = state
          ) do
        Logger.debug("retry_count: #{inspect(retry_count)}")

        if retry_count < 2 do
          :ok = Extreme.PersistentSubscription.nack(subscription, event, correlation_id, :Retry)
          send(state.sender, {:on_event, event})
          {:noreply, %{state | retry_count: retry_count + 1}}
        else
          :ok = Extreme.PersistentSubscription.ack(subscription, event, correlation_id)
          send(state.sender, {:on_event, event})
          {:noreply, %{state | retry_count: 0}}
        end
      end
    end

    test "Try retry nack action", %{server: server} do
      stream = "persistent-subscription-#{UUID.uuid4()}"
      group = "subscription-#{UUID.uuid4()}"

      events = [
        %PersonCreated{name: "1"},
        %PersonCreated{name: "2"},
        %PersonCreated{name: "3"}
      ]

      {:ok, _} = Extreme.execute(server, _write_events(stream, events))

      assert {:ok, response} =
               Extreme.execute(server, _create_persistent_subscription(group, stream))

      assert response == %Extreme.Msg.CreatePersistentSubscriptionCompleted{
               reason: "",
               result: :Success
             }

      TestPersistRetry.start_link(server, self(), group, stream)

      assert_receive {:on_event, event}
      assert :erlang.binary_to_term(event.event.data) == %PersonCreated{name: "1"}
      assert_receive {:on_event, event}
      assert :erlang.binary_to_term(event.event.data) == %PersonCreated{name: "1"}
      assert_receive {:on_event, event}
      assert :erlang.binary_to_term(event.event.data) == %PersonCreated{name: "1"}
      assert_receive {:on_event, event}
      assert :erlang.binary_to_term(event.event.data) == %PersonCreated{name: "2"}
      assert_receive {:on_event, event}
      assert :erlang.binary_to_term(event.event.data) == %PersonCreated{name: "2"}
      assert_receive {:on_event, event}
      assert :erlang.binary_to_term(event.event.data) == %PersonCreated{name: "2"}
      assert_receive {:on_event, event}
      assert :erlang.binary_to_term(event.event.data) == %PersonCreated{name: "3"}
      assert_receive {:on_event, event}
      assert :erlang.binary_to_term(event.event.data) == %PersonCreated{name: "3"}
      assert_receive {:on_event, event}
      assert :erlang.binary_to_term(event.event.data) == %PersonCreated{name: "3"}

      assert {:ok, response} =
               Extreme.execute(server, delete_persistent_subscription(group, stream))

      assert response == %Extreme.Msg.DeletePersistentSubscriptionCompleted{
               reason: "",
               result: :Success
             }
    end

    test "connect to existing persistent subscription on category stream and check nack retry works",
         %{server: server} do
      stream_prefix = "persistent#{String.replace(UUID.uuid4(), "-", "")}"
      stream = stream_prefix <> "-subscription"
      category_stream = "$ce-" <> stream_prefix
      group = "subscription-#{UUID.uuid4()}"
      buffer_size = 1

      # create persistent subscription with resolved links to events
      {:ok, _} =
        Extreme.execute(server, _create_persistent_subscription(group, category_stream, true))

      # subscribe to persistent subscription
      {:ok, subscriber} = Subscriber.start_link(self())

      {:ok, subscription} =
        Extreme.connect_to_persistent_subscription(
          server,
          subscriber,
          group,
          category_stream,
          buffer_size
        )

      events = [%PersonCreated{name: "1"}, %PersonCreated{name: "2"}]
      {:ok, _} = Extreme.execute(server, _write_events(stream, events))

      # assert events are received
      assert_receive {:on_event, event, correlation_id}
      assert :erlang.binary_to_term(event.event.data) == %PersonCreated{name: "1"}
      :ok = Extreme.PersistentSubscription.nack(subscription, event, correlation_id, :Retry)

      assert_receive {:on_event, event, correlation_id}
      assert :erlang.binary_to_term(event.event.data) == %PersonCreated{name: "1"}
      :ok = Extreme.PersistentSubscription.ack(subscription, event, correlation_id)

      assert_receive {:on_event, event, correlation_id}
      assert :erlang.binary_to_term(event.event.data) == %PersonCreated{name: "2"}
      :ok = Extreme.PersistentSubscription.nack(subscription, event, correlation_id, :Retry)

      assert_receive {:on_event, event, correlation_id}
      assert :erlang.binary_to_term(event.event.data) == %PersonCreated{name: "2"}
      :ok = Extreme.PersistentSubscription.ack(subscription, event, correlation_id)

      # assert events came in expected order
      assert Subscriber.received_events(subscriber) == [
               %PersonCreated{name: "1"},
               %PersonCreated{name: "1"},
               %PersonCreated{name: "2"},
               %PersonCreated{name: "2"}
             ]

      assert {:ok, response} =
               Extreme.execute(server, delete_persistent_subscription(group, category_stream))

      assert response == %Extreme.Msg.DeletePersistentSubscriptionCompleted{
               reason: "",
               result: :Success
             }
    end

    @tag timeout: 300_000
    @tag :benchmark
    test "reading and writing simultaneously is ok", %{server: server} do
      num_initial_events = 2_000
      num_bytes = 200
      # usualy older implementation fails on 50th iteration
      # so 500 should be enough to confirm that seting :inet.setopts(socket, active: false) 
      # works for this kind of issues
      # if you incrase this ensure you change this test timout
      num_test_events = 500
      stream = _random_stream_name()

      data = Enum.reduce(1..num_bytes, "", fn _, acc -> "a" <> acc end)
      event = %{__struct__: SomeStruct, data: data}

      initial_events = Enum.map(1..num_initial_events, fn _ -> event end)
      Extreme.execute(server, _write_events(stream, initial_events))

      Process.spawn(
        fn ->
          Enum.each(1..num_test_events, fn _x ->
            # IO.puts "w#{x}"
            assert {:ok, _} = Extreme.execute(server, _write_events(stream, [event]))
          end)
        end,
        []
      )

      p = self()

      Process.spawn(
        fn ->
          Enum.each(1..num_test_events, fn _x ->
            # IO.puts "r#{x}"
            assert {:ok, _} = Extreme.execute(server, _read_events(stream))
          end)

          # at the end, this should tell that we received all messages
          send(p, :ok)
        end,
        []
      )

      assert_receive(:ok, 300_000)
    end
  end

  defp _shutdown(pid) when is_pid(pid) do
    Process.unlink(pid)
    Process.exit(pid, :shutdown)
  end

  defp _random_stream_name, do: "extreme_test-" <> to_string(UUID.uuid1())

  defp _write_events(
         stream \\ "extreme_test",
         events \\ [%PersonCreated{name: "Pera Peric"}, %PersonChangedName{name: "Zika"}]
       ) do
    proto_events =
      Enum.map(events, fn event ->
        ExMsg.NewEvent.new(
          event_id: Extreme.Tools.gen_uuid(),
          event_type: to_string(event.__struct__),
          data_content_type: 0,
          metadata_content_type: 0,
          data: :erlang.term_to_binary(event),
          metadata: ""
        )
      end)

    ExMsg.WriteEvents.new(
      event_stream_id: stream,
      expected_version: -2,
      events: proto_events,
      require_master: false
    )
  end

  defp _read_events(stream) do
    ExMsg.ReadStreamEvents.new(
      event_stream_id: stream,
      from_event_number: 0,
      max_count: 4096,
      resolve_link_tos: true,
      require_master: false
    )
  end

  defp _read_events_backward(stream, start \\ -1, count \\ 1) do
    ExMsg.ReadStreamEventsBackward.new(
      event_stream_id: stream,
      from_event_number: start,
      max_count: count,
      resolve_link_tos: true,
      require_master: false
    )
  end

  defp _read_event(stream, position) do
    ExMsg.ReadEvent.new(
      event_stream_id: stream,
      event_number: position,
      resolve_link_tos: true,
      require_master: false
    )
  end

  defp _delete_stream(stream, hard_delete \\ false) do
    ExMsg.DeleteStream.new(
      event_stream_id: stream,
      expected_version: -2,
      require_master: false,
      hard_delete: hard_delete
    )
  end

  defp _create_persistent_subscription(groupName, stream, resolve_link_tos \\ false)

  defp _create_persistent_subscription(groupName, stream, resolve_link_tos) do
    ExMsg.CreatePersistentSubscription.new(
      subscription_group_name: groupName,
      event_stream_id: stream,
      resolve_link_tos: resolve_link_tos,
      start_from: 0,
      message_timeout_milliseconds: 10_000,
      record_statistics: false,
      live_buffer_size: 500,
      read_batch_size: 20,
      buffer_size: 500,
      max_retry_count: 10,
      prefer_round_robin: true,
      checkpoint_after_time: 1_000,
      checkpoint_max_count: 500,
      checkpoint_min_count: 1,
      subscriber_max_count: 1
    )
  end

  defp delete_persistent_subscription(group, stream) do
    ExMsg.DeletePersistentSubscription.new(
      subscription_group_name: group,
      event_stream_id: stream
    )
  end
end
