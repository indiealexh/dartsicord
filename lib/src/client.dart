import "dart:async";
import "dart:convert";
import "dart:io";

import "internals.dart";
import "event.dart";
import "enums.dart";
import "object.dart";
import "ws/guild.dart";
import "ws/channel.dart";
import "ws/message.dart";
import "ws/user.dart";
import "ws/embed.dart";

import "events/channel.dart";
import "events/guild.dart";
import "events/message.dart";

class DiscordClient extends EventExhibitor {
  Timer _heartbeat;
  WebSocket _socket;
  int _lastSeq = null;

  /// The shard of the current client.
  int shard;

  /// The total number of shards that this bot is using.
  int shardCount;

  /// The token of this client.
  String token;

  /// The token type of this client.
  TokenType tokenType;

  /// A list of Guilds this client is in.
  List<Guild> guilds;

  /// Whether or not this client has recieved the [READY] payload yet.
  bool ready = false;

  /// The [User] representing this guild.
  User user;

  //
  // Events
  //

  /// Fired when the client receives the [READY] payload.
  EventStream<ReadyEvent> onReady;

  /// Fired when the client sees a guild created. Not fired before [ready] is reached.
  EventStream<GuildCreateEvent> onGuildCreate;
  /// Fired when the client sees a guild update.
  EventStream<GuildUpdateEvent> onGuildUpdate;
  /// Fired when the client is removed from a guild.
  EventStream<GuildRemoveEvent> onGuildRemove;
  /// Fired when the client sees a guild become unavailable.
  EventStream<GuildUnavailableEvent> onGuildUnavailable;

  /// Fired when the client sees a user banned.
  EventStream<UserBannedEvent> onUserBanned;
  /// Fired when the client sees a user unbanned.
  EventStream<UserUnbannedEvent> onUserUnbanned;
  /// Fired when the client sees a guild update its emojis.
  EventStream<GuildEmojisUpdateEvent> onGuildEmojisUpdated;
  /// Fired when the client sees a guild update its integrations.
  EventStream<GuildIntegrationsUpdatedEvent> onGuildIntegrationsUpdated;
  /// Fired when the client sees a user join a guild.
  EventStream<UserAddedEvent> onUserAdded;
  /// Fired when the client sees a user get removed from a guild. (left, kicked, banned, etc.)
  EventStream<UserRemovedEvent> onUserRemoved;

  /// Fired when the client sees a message created.
  EventStream<MessageCreateEvent> onMessage;
  /// Fired when the client sees a message delete.
  EventStream<MessageDeleteEvent> onMessageDelete;

  /// Fired when the client sees a channel created.
  EventStream<ChannelCreateEvent> onChannelCreate;
  /// Fired when the client sees a channel updated.
  EventStream<ChannelUpdateEvent> onChannelUpdate;
  /// Fired when the client sees a channel deleted.
  EventStream<ChannelDeleteEvent> onChannelDelete;
  /// Fired when the client sees a channel update its pins.
  EventStream<ChannelPinsUpdateEvent> onChannelPinsUpdate;

  // Internal methods

  Future _getGateway() async {
    final route = new Route() + "gateway";
    final response = await route.get(client: this);
    return JSON.decode(response.body)["url"];
  }

  void _sendHeartbeat(Timer timer) {
    _socket.add(new Packet(data: _lastSeq).toString());
  }

  void _defineEvents() {
    onReady = createEvent();

    onGuildCreate = createEvent();
    onGuildUpdate = createEvent();
    onGuildRemove = createEvent();
    onGuildUnavailable = createEvent();

    onGuildEmojisUpdated = createEvent();
    onGuildIntegrationsUpdated = createEvent();
    onUserAdded = createEvent();
    onUserRemoved = createEvent();

    onUserBanned = createEvent();
    onUserUnbanned = createEvent();

    onMessage = createEvent();
    onMessageDelete = createEvent();

    onChannelCreate = createEvent();
    onChannelUpdate = createEvent();
    onChannelDelete = createEvent();
    onChannelPinsUpdate = createEvent();
  }



  // External methods

  /// Modify the client's user.
  Future modify({String username}) async {
    final route = User.endpoint + "@me";
    final response = await route.patch({"username": username}, client: this);
    return User.fromMap(JSON.decode(response.body), this);
  }

  /// Get a guild from the client's cache.
  Guild getGuild(dynamic id) {
    return guilds.firstWhere((g) {
      return g.id.toString() == id.toString();
    });
  }
  
  /// Get a channel given its [id].
  Future<Channel> getChannel(dynamic id) async {
    final route = Channel.endpoint + id;
    final response = await route.get(client: this);
    return Channel.fromMap(JSON.decode(response.body), this);
  }

  /// Get a text channel given its [id].
  Future<TextChannel> getTextChannel(dynamic id) async =>
    await getChannel(id) as TextChannel;



  // External method references

  /// Sends a message to a text channel. See [TextChannel.sendMessage]
  Future<Message> sendMessage(String content, TextChannel channel, {Embed embed}) =>
    channel.sendMessage(content, embed: embed);

  /// Creates a direct message channel with the given [recipient].
  Future<TextChannel> createDirectMessage(User recipient) =>
    recipient.createDirectMessage();



  // Constructor

  DiscordClient({this.shard, this.shardCount}) {
    _defineEvents();

    guilds = [];
  }

  
  /// Connects to Discord's API.
  Future connect(String token, {TokenType tokenType = TokenType.Bot}) async {
    this.token = token;
    this.tokenType = tokenType;

    final gateway = await _getGateway();
    _socket = await WebSocket.connect(gateway + "?v=6&encoding=json");

    _socket.listen((payloadRaw) async {
      final payload = JSON.decode(payloadRaw);
      final packet = new Packet(
        data: payload["d"],
        event: payload["t"],
        opcode: payload["op"],
        seq: payload["s"],
        client: this);

      if (packet.seq != null)
        _lastSeq = packet.seq;

      switch (packet.opcode) {
        case 0: // Dispatch
          final event = payload["t"];
          
          switch (event) {
            case "READY":
              await ReadyEvent.construct(packet);
              break;

            case "CHANNEL_CREATE":
              await ChannelCreateEvent.construct(packet);
              break;
            case "CHANNEL_UPDATE":
              await ChannelUpdateEvent.construct(packet);
              break;
            case "CHANNEL_DELETE":
              await ChannelDeleteEvent.construct(packet);
              break;
            case "CHANNEL_PINS_UPDATE":
              await ChannelPinsUpdateEvent.construct(packet);
              break;

            case "GUILD_CREATE":
              await GuildCreateEvent.construct(packet);
              break;
            case "GUILD_UPDATE":
              await GuildUpdateEvent.construct(packet);
              break;
            case "GUILD_DELETE":
              await GuildRemoveEvent.construct(packet); // This method checks if this event was fired because of unavailability or removal from a guild.
              break;
            
            case "GUILD_EMOJIS_UPDATE":
              await GuildEmojisUpdateEvent.construct(packet);
              break;
            case "GUILD_INTEGRATIONS_UPDATE":
              await GuildIntegrationsUpdateEvent.construct(packet);
              break;
            case "GUILD_MEMBER_ADD":
              await UserAddedEvent.construct(packet);
              break;
            case "GUILD_MEMBER_REMOVE":
              await UserRemovedEvent.construct(packet);
              break;

            case "USER_BANNED":
              await UserBannedEvent.construct(packet);
              break;
            case "USER_UNBANNED":
              await UserUnbannedEvent.construct(packet);
              break;

            case "MESSAGE_CREATE":
              await MessageCreateEvent.construct(packet);
              break;
            case "MESSAGE_DELETE":
              await MessageDeleteEvent.construct(packet);
              break;

            default:
              break;
          }

          break;
        case 1: // Heartbeat
          _sendHeartbeat(_heartbeat);
          break;
        case 7: // Reconnect
          break;
        case 9: // Invalid Session
          break;
        case 10: // Hello
          _heartbeat = new Timer.periodic(new Duration(milliseconds: packet.data["heartbeat_interval"]), _sendHeartbeat);
          _socket.add(new Packet(opcode: 2, seq: _lastSeq, data: {
              "token": token,
              "properties": {
                "\$os": "windows",
                "\$browser": "dartsicord",
                "\$device": "dartsicord"
              },
              //"shard": shard != null ? [shard, shardCount] : null,
              "compress": false,
              "large_threshold": 250
          }).toString());
          break;
        case 11: // Heartbeat ACK
          break;
        default:
          break;
      }
    }, onError: (e) {
      print(e.toString());
    }, onDone: () {
      print("ended");
    }, cancelOnError: true);
  }
}