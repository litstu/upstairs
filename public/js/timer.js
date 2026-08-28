// ============================================
// ポモドーロタイマーのカウントダウンロジック
// スタートを押すとタイマー開始、裏でAIがねぎらいの言葉を用意する
// 25分経ったらマスコットが吹き出しでAIのセリフを喋る
// ============================================
document.addEventListener('DOMContentLoaded', function () {
  var TIMER_MINUTES = 25;
  var TOTAL_SECONDS = TIMER_MINUTES * 60;
  var intervalId = null;

  var taskIdElement = document.querySelector('[data-task-id]');
  var taskId = taskIdElement ? taskIdElement.getAttribute('data-task-id') : null;

  var timerDisplay      = document.getElementById('timer-display');
  var startBtn          = document.getElementById('start-btn');
  var stopBtn           = document.getElementById('stop-btn');
  var speechBubble      = document.getElementById('speech-bubble');
  var timerControls     = document.getElementById('timer-controls');
  var completeActions   = document.getElementById('complete-actions');
  var modeSelector      = document.getElementById('mode-selector');

  var aiMessage = null;
  var aiMessageReady = false;

  function formatTime(seconds) {
    var minutes = Math.floor(seconds / 60);
    var secs = seconds % 60;
    return String(minutes).padStart(2, '0') + ':' + String(secs).padStart(2, '0');
  }

  function fetchAiMessage() {
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
        aiMessage = 'お疲れさでした！25分間よく集中できたね！';
        aiMessageReady = true;
      });
  }

  function handleComplete() {
    clearInterval(intervalId);
    intervalId = null;
    localStorage.removeItem('focus_timer_end_time');
    localStorage.removeItem('focus_timer_mode');
    window.onbeforeunload = null;

    if (speechBubble) {
      speechBubble.classList.remove('hidden');
      speechBubble.innerHTML = '<span class="loading loading-dots loading-xs text-sky-400"></span>';

      var waitAndShow = setInterval(function () {
        if (aiMessageReady) {
          clearInterval(waitAndShow);
          speechBubble.textContent = aiMessage;
        }
      }, 200);
    }

    if (timerControls) timerControls.classList.add('hidden');
    if (modeSelector) modeSelector.classList.add('hidden');
    if (completeActions) {
      completeActions.classList.remove('hidden');
      completeActions.classList.add('flex');
    }

    var durationInput = document.getElementById('duration-input');
    if (durationInput) durationInput.value = TIMER_MINUTES;
  }

  function startCountdown(getRemainingSecs) {
    startBtn.disabled = true;
    if (stopBtn) stopBtn.disabled = false;
    if (modeSelector) modeSelector.classList.add('hidden');

    fetchAiMessage();

    intervalId = setInterval(function () {
      var remainingSeconds = getRemainingSecs();
      if (timerDisplay) timerDisplay.textContent = formatTime(remainingSeconds);

      if (remainingSeconds <= 0) {
        handleComplete();
      }
    }, 1000);
  }

  // ---- スタートボタンの押下時 ----
  if (startBtn) {
    startBtn.addEventListener('click', function () {
      if (intervalId !== null) return;

      var selectedMode = document.querySelector('input[name="timer_mode"]:checked').value;
      localStorage.setItem('focus_timer_mode', selectedMode);

      if (selectedMode === 'background') {
        // 放置OKモード：終了予定時刻を localStorage に保存
        var endTime = Date.now() + TOTAL_SECONDS * 1000;
        localStorage.setItem('focus_timer_end_time', endTime);

        startCountdown(function () {
          var target = parseInt(localStorage.getItem('focus_timer_end_time'), 10);
          return Math.max(0, Math.floor((target - Date.now()) / 1000));
        });
      } else {
        // 画面維持モード：ページ移動やタブ閉じに対して警告を出す
        var remainingSeconds = TOTAL_SECONDS;
        window.onbeforeunload = function () {
          return "集中タイマーを中断しますか？";
        };

        startCountdown(function () {
          remainingSeconds--;
          return Math.max(0, remainingSeconds);
        });
      }
    });
  }

  // ---- 停止ボタンの押下時 ----
  if (stopBtn) {
    stopBtn.addEventListener('click', function () {
      if (intervalId === null) return;

      clearInterval(intervalId);
      intervalId = null;

      localStorage.removeItem('focus_timer_end_time');
      localStorage.removeItem('focus_timer_mode');
      window.onbeforeunload = null;

      startBtn.disabled = false;
      stopBtn.disabled = true;
      if (modeSelector) modeSelector.classList.remove('hidden');
    });
  }

  // ---- ページ読み込み時の復元処理（放置OKモード用） ----
  var savedEndTime = localStorage.getItem('focus_timer_end_time');
  if (savedEndTime) {
    var remainingMs = parseInt(savedEndTime, 10) - Date.now();
    if (remainingMs > 0) {
      startCountdown(function () {
        var target = parseInt(localStorage.getItem('focus_timer_end_time'), 10);
        return Math.max(0, Math.floor((target - Date.now()) / 1000));
      });
    } else {
      localStorage.removeItem('focus_timer_end_time');
      localStorage.removeItem('focus_timer_mode');
    }
  }
});