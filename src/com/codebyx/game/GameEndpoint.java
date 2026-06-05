package com.codebyx.game;

import java.io.IOException;
import java.time.LocalTime;
import java.time.format.DateTimeFormatter;
import java.util.Map;
import java.util.Random;
import java.util.concurrent.ConcurrentHashMap;

import jakarta.websocket.OnClose;
import jakarta.websocket.OnError;
import jakarta.websocket.OnMessage;
import jakarta.websocket.OnOpen;
import jakarta.websocket.Session;
import jakarta.websocket.server.PathParam;
import jakarta.websocket.server.ServerEndpoint;

@ServerEndpoint("/game/{playerName}")
public class GameEndpoint {

    private static final int WIDTH = 860;
    private static final int HEIGHT = 520;
    private static final int PLAYER_RADIUS = 18;
    private static final int GEM_RADIUS = 12;
    private static final int STEP = 14;

    private static final Random RANDOM = new Random();
    private static final DateTimeFormatter TIME_FORMATTER = DateTimeFormatter.ofPattern("HH:mm:ss");

    private static final Map<String, Session> SESSIONS = new ConcurrentHashMap<>();
    private static final Map<String, Player> PLAYERS = new ConcurrentHashMap<>();

    private static volatile Gem gem = new Gem(randomBetween(40, WIDTH - 40), randomBetween(40, HEIGHT - 40), "#ffd54f");

    @OnOpen
    public void onOpen(Session session, @PathParam("playerName") String rawName) {
        String playerName = uniqueName(rawName);
        Player player = new Player(
                playerName,
                randomBetween(40, WIDTH - 40),
                randomBetween(40, HEIGHT - 40),
                randomPlayerColor()
        );

        session.getUserProperties().put("playerName", playerName);
        SESSIONS.put(playerName, session);
        PLAYERS.put(playerName, player);

        sendToSession(session, buildSystemMessage("歡迎 " + playerName + " 進入多人即時遊戲"));
        broadcast(buildSystemMessage(playerName + " 已加入遊戲"));
        broadcastState();
    }

    @OnMessage
    public void onMessage(String message, Session session) {
        String playerName = (String) session.getUserProperties().get("playerName");
        if (playerName == null || message == null) {
            return;
        }

        Player player = PLAYERS.get(playerName);
        if (player == null) {
            return;
        }

        boolean changed = false;

        synchronized (GameEndpoint.class) {
            String cmd = message.trim().toUpperCase();

            switch (cmd) {
                case "UP":
                    player.y = Math.max(PLAYER_RADIUS, player.y - STEP);
                    changed = true;
                    break;
                case "DOWN":
                    player.y = Math.min(HEIGHT - PLAYER_RADIUS, player.y + STEP);
                    changed = true;
                    break;
                case "LEFT":
                    player.x = Math.max(PLAYER_RADIUS, player.x - STEP);
                    changed = true;
                    break;
                case "RIGHT":
                    player.x = Math.min(WIDTH - PLAYER_RADIUS, player.x + STEP);
                    changed = true;
                    break;
                case "RESET":
                    player.x = randomBetween(40, WIDTH - 40);
                    player.y = randomBetween(40, HEIGHT - 40);
                    player.score = 0;
                    changed = true;
                    break;
                default:
                    break;
            }

            if (changed) {
                checkGemCollected(player);
            }
        }

        if (changed) {
            broadcastState();
        }
    }

    @OnClose
    public void onClose(Session session) {
        String playerName = (String) session.getUserProperties().get("playerName");
        if (playerName != null) {
            SESSIONS.remove(playerName);
            PLAYERS.remove(playerName);
            broadcast(buildSystemMessage(playerName + " 已離開遊戲"));
            broadcastState();
        }
    }

    @OnError
    public void onError(Session session, Throwable throwable) {
        throwable.printStackTrace();
    }

    private static synchronized void checkGemCollected(Player player) {
        int dx = player.x - gem.x;
        int dy = player.y - gem.y;
        int distanceSquared = dx * dx + dy * dy;
        int target = PLAYER_RADIUS + GEM_RADIUS;

        if (distanceSquared <= target * target) {
            player.score += 10;
            gem = new Gem(randomBetween(40, WIDTH - 40), randomBetween(40, HEIGHT - 40), randomGemColor());
            broadcast(buildSystemMessage(player.name + " 搶到寶石，分數 +10"));
        }
    }

    private static void broadcastState() {
        broadcast(buildStateJson());
    }

    private static void broadcast(String json) {
        for (Session session : SESSIONS.values()) {
            sendToSession(session, json);
        }
    }

    private static void sendToSession(Session session, String text) {
        if (session == null || !session.isOpen()) {
            return;
        }

        synchronized (session) {
            try {
                session.getBasicRemote().sendText(text);
            } catch (IOException e) {
                e.printStackTrace();
            }
        }
    }

    private static String buildStateJson() {
        StringBuilder sb = new StringBuilder();
        sb.append("{");
        sb.append("\"type\":\"state\",");
        sb.append("\"width\":").append(WIDTH).append(",");
        sb.append("\"height\":").append(HEIGHT).append(",");
        sb.append("\"gem\":{")
          .append("\"x\":").append(gem.x).append(",")
          .append("\"y\":").append(gem.y).append(",")
          .append("\"color\":\"").append(gem.color).append("\"")
          .append("},");
        sb.append("\"players\":[");
        boolean first = true;
        for (Player player : PLAYERS.values()) {
            if (!first) {
                sb.append(",");
            }
            sb.append("{")
              .append("\"name\":\"").append(escape(player.name)).append("\",")
              .append("\"x\":").append(player.x).append(",")
              .append("\"y\":").append(player.y).append(",")
              .append("\"score\":").append(player.score).append(",")
              .append("\"color\":\"").append(player.color).append("\"")
              .append("}");
            first = false;
        }
        sb.append("]");
        sb.append("}");
        return sb.toString();
    }

    private static String buildSystemMessage(String message) {
        return "{"
                + "\"type\":\"system\","
                + "\"time\":\"" + LocalTime.now().format(TIME_FORMATTER) + "\","
                + "\"message\":\"" + escape(message) + "\""
                + "}";
    }

    private static synchronized String uniqueName(String rawName) {
        String base = sanitize(rawName);
        String candidate = base;
        int index = 1;
        while (SESSIONS.containsKey(candidate)) {
            candidate = base + "_" + index++;
        }
        return candidate;
    }

    private static String sanitize(String rawName) {
        if (rawName == null || rawName.trim().isEmpty()) {
            return "Player";
        }
        String cleaned = rawName.trim().replaceAll("[^\\p{L}\\p{N}_\\-\\u4e00-\\u9fff]", "");
        return cleaned.isEmpty() ? "Player" : cleaned;
    }

    private static int randomBetween(int min, int max) {
        return RANDOM.nextInt(max - min + 1) + min;
    }

    private static String randomPlayerColor() {
        String[] colors = {"#42a5f5", "#ef5350", "#66bb6a", "#ab47bc", "#ffa726", "#26c6da"};
        return colors[RANDOM.nextInt(colors.length)];
    }

    private static String randomGemColor() {
        String[] colors = {"#ffd54f", "#ff8a65", "#81c784", "#4dd0e1", "#f06292"};
        return colors[RANDOM.nextInt(colors.length)];
    }

    private static String escape(String text) {
        if (text == null) {
            return "";
        }
        return text.replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("\r", "\\r")
                .replace("\n", "\\n");
    }

    private static class Player {
        String name;
        int x;
        int y;
        int score;
        String color;

        Player(String name, int x, int y, String color) {
            this.name = name;
            this.x = x;
            this.y = y;
            this.color = color;
            this.score = 0;
        }
    }

    private static class Gem {
        int x;
        int y;
        String color;

        Gem(int x, int y, String color) {
            this.x = x;
            this.y = y;
            this.color = color;
        }
    }
}
