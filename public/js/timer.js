// ============================================
// ポモドーロタイマーのカウントダウンロジック
// スタートを押すとタイマー開始、裏でAIがねぎらいの言葉を用意する
// 25分経ったらマスコットが吹き出しでAIのセリフを喋る
// ============================================

document.addEventListener('DOMContentLoaded', function () {
  var TIMER_MINUTES = 25;
  var TOTAL_SECONDS = TIMER_MINUTES * 60;//HERE I CHANGED!!
  var remainingSeconds = TOTAL_SECONDS;
  var intervalId = null;

  // タスク ID を data-task-id から取得する
  var taskIdElement = document.querySelector('[data-task-id]');
  var taskId = taskIdElement ? taskIdElement.getAttribute('data-task-id') : null;

  // DOM 要素を取得する
  var timerDisplay      = document.getElementById('timer-display');
  var startBtn          = document.getElementById('start-btn');
  var stopBtn           = document.getElementById('stop-btn');
  var speechBubble      = document.getElementById('speech-bubble');
  var timerControls     = document.getElementById('timer-controls');
  var completeActions   = document.getElementById('complete-actions');

  // AI のねぎらいメッセージ（スタート時から非同期で取得する）
  var aiMessage = null;
  var aiMessageReady = false;

  // ============================================
  // 秒数を「MM:SS」形式に変換する
  // ============================================
  function formatTime(seconds) {
    var minutes = Math.floor(seconds / 60);
    var secs = seconds % 60;
    return String(minutes).padStart(2, '0') + ':' + String(secs).padStart(2, '0');
  }

  // ============================================
  // タイマー表示を更新する
  // ============================================
  function updateDisplay() {
    if (timerDisplay) {
      timerDisplay.textContent = formatTime(remainingSeconds);
    }
  }

  // ============================================
  // 裏でAIのねぎらいメッセージを取得する
  // スタートボタンを押したタイミングで開始する
  // ============================================
  function fetchAiMessage() {
    // Sinatra の params は application/x-www-form-urlencoded を自動解析する
    var body = 'task_id=' + encodeURIComponent(taskId || '') +
               '&duration_minutes=' + encodeURIComponent(TIMER_MINUTES);
    fetch('/ai/encourage', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: body
    })
      .then(function (res) { return res.json(); })
      .then(function (data) {
        aiMessage = data.message || '集中タイマー完走おめでとう！よく頑張ったね！';
        aiMessageReady = true;
      })
      .catch(function () {
        aiMessage = 'お疲れさまでした！25分間よく集中できたね！';
        aiMessageReady = true;
      });
  }

  // ============================================
  // タイマーが 0 になったときの完了処理
  // ============================================
  function handleComplete() {
    clearInterval(intervalId);
    intervalId = null;

    // コメントエリアを表示する（AIメッセージが来るまでローディング表示）
    if (speechBubble) {
      speechBubble.classList.remove('hidden');
      speechBubble.innerHTML = '<span class="loading loading-dots loading-xs text-sky-400"></span>';

      // AIメッセージが準備できていれば即表示、まだなら待つ
      var waitAndShow = setInterval(function () {
        if (aiMessageReady) {
          clearInterval(waitAndShow);
          speechBubble.textContent = aiMessage;
        }
      }, 200);
    }

    // コントロールボタンを隠して完了アクションを表示する
    if (timerControls) timerControls.classList.add('hidden');
    if (completeActions) {
      completeActions.classList.remove('hidden');
      completeActions.classList.add('flex');
    }

    // duration-input に実際の分数をセットする（フォーム送信時に使われる）
    var durationInput = document.getElementById('duration-input');
    if (durationInput) durationInput.value = TIMER_MINUTES;
  }

  // ============================================
  // スタートボタンの処理
  // ============================================
  if (startBtn) {
    startBtn.addEventListener('click', function () {
      if (intervalId !== null) return;

      startBtn.disabled = true;
      if (stopBtn) stopBtn.disabled = false;

      // 裏でAIのねぎらいメッセージを取得し始める
      fetchAiMessage();

      // 1秒ごとにカウントダウンする
      intervalId = setInterval(function () {
        remainingSeconds--;
        updateDisplay();

        if (remainingSeconds <= 0) {
          remainingSeconds = 0;
          handleComplete();
        }
      }, 1000);
    });
  }

  // ============================================
  // 停止ボタンの処理
  // ============================================
  if (stopBtn) {
    stopBtn.addEventListener('click', function () {
      if (intervalId === null) return;

      clearInterval(intervalId);
      intervalId = null;

      startBtn.disabled = false;
      stopBtn.disabled = true;
    });
  }

  // 初期表示をセットする
  updateDisplay();
});
