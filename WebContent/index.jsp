<%@ page contentType="text/html; charset=UTF-8" pageEncoding="UTF-8" %>
<!DOCTYPE html>
<html lang="zh-Hant">
<head>
<meta charset="UTF-8">
<title>多人即時 WebSocket 搶寶石遊戲</title>
<style>
body { margin: 0; background: #0f172a; color: #e2e8f0; font-family: Arial, "Microsoft JhengHei", sans-serif; }
.wrap { width: 1180px; margin: 20px auto; display: grid; grid-template-columns: 280px 1fr; gap: 18px; }
.card { background: #111827; border: 1px solid #334155; border-radius: 14px; box-shadow: 0 8px 24px rgba(0,0,0,0.25); overflow: hidden; }
.title { background: #1e293b; padding: 14px 18px; font-size: 20px; font-weight: bold; border-bottom: 1px solid #334155; }
.body, .game-panel { padding: 16px; }
label { display: block; margin-bottom: 6px; font-weight: bold; }
input[type="text"] { width: 100%; box-sizing: border-box; padding: 10px 12px; border-radius: 8px; border: 1px solid #475569; background: #0f172a; color: #e2e8f0; margin-bottom: 12px; }
button { padding: 10px 14px; border: none; border-radius: 8px; color: white; cursor: pointer; margin-right: 8px; margin-bottom: 10px; }
.connect { background: #16a34a; }
.disconnect { background: #dc2626; }
.reset { background: #2563eb; }
.hint, .status { font-size: 14px; line-height: 1.7; color: #cbd5e1; }
#log { margin-top: 12px; background: #020617; border: 1px solid #334155; border-radius: 10px; height: 220px; overflow-y: auto; padding: 12px; font-size: 13px; }
.log-line { margin-bottom: 8px; }
canvas { background: linear-gradient(180deg, #0b1220 0%, #13233f 100%); border: 2px solid #334155; border-radius: 12px; display: block; margin: 0 auto 12px auto; }
.info-grid { display: grid; grid-template-columns: 1fr 300px; gap: 14px; }
.rank { background: #020617; border: 1px solid #334155; border-radius: 10px; padding: 12px; }
table { width: 100%; border-collapse: collapse; font-size: 14px; }
th, td { padding: 8px 6px; border-bottom: 1px solid #1e293b; text-align: left; }
.footer-note { text-align: center; color: #94a3b8; font-size: 13px; }
</style>
</head>
<body>
<div class="wrap">
    <div class="card">
        <div class="title">連線與操作</div>
        <div class="body">
            <label for="playerName">玩家名稱</label>
            <input type="text" id="playerName" value="Allen">

            <button class="connect" onclick="connectGame()">連線</button>
            <button class="disconnect" onclick="disconnectGame()">斷線</button>
            <button class="reset" onclick="resetMe()">重設</button>

            <div class="status" id="status">尚未連線</div>

            <div class="hint" style="margin-top:12px;">
                操作方式：<br>
                - 鍵盤方向鍵 或 WASD 移動<br>
                - 碰到寶石就得分 +10<br>
                - 可開兩個以上瀏覽器視窗測試多人同步
            </div>

            <div id="log"></div>
        </div>
    </div>

    <div class="card">
        <div class="title">多人即時搶寶石遊戲</div>
        <div class="game-panel">
            <canvas id="gameCanvas" width="860" height="520"></canvas>

            <div class="info-grid">
                <div class="rank">
                    <h3 style="margin-top:0;">遊戲說明</h3>
                    <div class="hint">
                        這個範例示範：
                        <br>1. 多人 WebSocket 長連線
                        <br>2. 玩家位置即時同步
                        <br>3. 寶石碰撞與分數更新
                        <br>4. 排行榜即時廣播
                    </div>
                </div>

                <div class="rank">
                    <h3 style="margin-top:0;">排行榜</h3>
                    <table>
                        <thead>
                            <tr><th>排名</th><th>玩家</th><th>分數</th></tr>
                        </thead>
                        <tbody id="rankingBody"></tbody>
                    </table>
                </div>
            </div>

            <div class="footer-note">JDK 17 / Eclipse Dynamic Web Project / Tomcat 10.1 / Jakarta WebSocket</div>
        </div>
    </div>
</div>

<script>
let ws = null;
let gameState = { players: [], gem: null, width: 860, height: 520 };
const ctxPath = '<%= request.getContextPath() %>';
const canvas = document.getElementById('gameCanvas');
const ctx = canvas.getContext('2d');

function log(text) {
    const logBox = document.getElementById('log');
    const line = document.createElement('div');
    line.className = 'log-line';
    line.innerText = text;
    logBox.appendChild(line);
    logBox.scrollTop = logBox.scrollHeight;
}

function setStatus(text) {
    document.getElementById('status').innerText = text;
}

function connectGame() {
    const playerName = document.getElementById('playerName').value.trim() || 'Player';

    if (ws && ws.readyState === WebSocket.OPEN) {
        log('你已經在線上。');
        return;
    }

    const protocol = location.protocol === 'https:' ? 'wss://' : 'ws://';
    const url = protocol + location.host + ctxPath + '/game/' + encodeURIComponent(playerName);
    ws = new WebSocket(url);

    ws.onopen = function() {
        setStatus('已連線');
        log('WebSocket 連線成功。');
    };

    ws.onmessage = function(event) {
        const data = JSON.parse(event.data);
        if (data.type === 'system') {
            log('[' + data.time + '] ' + data.message);
        } else if (data.type === 'state') {
            gameState = data;
            renderGame();
            renderRanking();
        }
    };

    ws.onclose = function() {
        setStatus('已斷線');
        log('WebSocket 已斷線。');
        gameState = { players: [], gem: null, width: 860, height: 520 };
        renderGame();
        renderRanking();
    };

    ws.onerror = function() {
        log('發生 WebSocket 錯誤。');
    };
}

function disconnectGame() {
    if (ws) {
        ws.close();
        ws = null;
    }
}

function resetMe() {
    if (ws && ws.readyState === WebSocket.OPEN) {
        ws.send('RESET');
    }
}

function sendMove(cmd) {
    if (ws && ws.readyState === WebSocket.OPEN) {
        ws.send(cmd);
    }
}

document.addEventListener('keydown', function(event) {
    const key = event.key.toLowerCase();
    if (key === 'arrowup' || key === 'w') sendMove('UP');
    if (key === 'arrowdown' || key === 's') sendMove('DOWN');
    if (key === 'arrowleft' || key === 'a') sendMove('LEFT');
    if (key === 'arrowright' || key === 'd') sendMove('RIGHT');
});

function renderGame() {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = '#0b1220';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    drawGrid();

    if (gameState.gem) {
        drawGem(gameState.gem.x, gameState.gem.y, gameState.gem.color);
    }

    (gameState.players || []).forEach(function(player) {
        drawPlayer(player);
    });
}

function drawGrid() {
    ctx.strokeStyle = 'rgba(148, 163, 184, 0.12)';
    ctx.lineWidth = 1;
    for (let x = 20; x < canvas.width; x += 40) {
        ctx.beginPath();
        ctx.moveTo(x, 0);
        ctx.lineTo(x, canvas.height);
        ctx.stroke();
    }
    for (let y = 20; y < canvas.height; y += 40) {
        ctx.beginPath();
        ctx.moveTo(0, y);
        ctx.lineTo(canvas.width, y);
        ctx.stroke();
    }
}

function drawPlayer(player) {
    ctx.beginPath();
    ctx.fillStyle = player.color;
    ctx.arc(player.x, player.y, 18, 0, Math.PI * 2);
    ctx.fill();
    ctx.strokeStyle = '#e2e8f0';
    ctx.lineWidth = 2;
    ctx.stroke();
    ctx.fillStyle = '#ffffff';
    ctx.font = 'bold 13px Arial';
    ctx.fillText(player.name + ' (' + player.score + ')', player.x - 28, player.y - 24);
}

function drawGem(x, y, color) {
    ctx.save();
    ctx.translate(x, y);
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.moveTo(0, -14);
    ctx.lineTo(11, 0);
    ctx.lineTo(0, 14);
    ctx.lineTo(-11, 0);
    ctx.closePath();
    ctx.fill();
    ctx.strokeStyle = '#fff8e1';
    ctx.lineWidth = 2;
    ctx.stroke();
    ctx.restore();
}

function renderRanking() {
    const body = document.getElementById('rankingBody');
    body.innerHTML = '';

    const players = (gameState.players || []).slice().sort(function(a, b) {
        return b.score - a.score;
    });

    players.forEach(function(player, index) {
        const tr = document.createElement('tr');
        tr.innerHTML = '<td>' + (index + 1) + '</td><td>' + player.name + '</td><td>' + player.score + '</td>';
        body.appendChild(tr);
    });
}

renderGame();
</script>
</body>
</html>
