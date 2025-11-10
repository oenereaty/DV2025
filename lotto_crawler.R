library(RSelenium)
library(rvest)
library(xml2)
# library(wdman) # 이미 실행되었다고 가정


# wdman::chrome() 함수를 사용하여 chromedriver를 실행합니다.
c_drvr <- wdman::chrome(
  port = 4444L, 
  version = "latest" 
)

# remoteDriver로 실행된 chromedriver에 연결
remDr <- remoteDriver(
  remoteServerAddr = "localhost",
  port = 4444L,
  browserName = "chrome"
)

# 브라우저 세션 열기
remDr$open()

# 로또 당첨 결과 페이지로 이동
bywin_url <- "https://dhlottery.co.kr/gameResult.do?method=byWin"
remDr$navigate(bywin_url)

# 페이지 로드 대기
Sys.sleep(3)

# --- 2. 초기 설정 및 저장 경로 지정 ---

# HTML 저장 경로 설정 (사용자 요청 경로)
# Windows 경로를 R에서 잘 인식하도록 처리합니다.
save_dir <- normalizePath("C:/crawling2", winslash = "/")
if (!dir.exists(save_dir)) {
  dir.create(save_dir, recursive = TRUE)
  cat(sprintf("⚠️ 경로가 존재하지 않아 새로 생성했습니다: %s\n", save_dir))
}

cat("\n📌 HTML 저장 경로:", save_dir, "\n")
cat("--------------------------------------------\n")

# --- 3. 회차 구간 옵션 읽기 ---

# <select id="hdrwComb"> 안의 구간(option) 요소들을 찾고 텍스트와 값(value)을 추출
opts <- remDr$findElements(using = "css selector", value = "#hdrwComb option")
opt_texts <- sapply(opts, function(x) x$getElementText()[[1]])
opt_values <- sapply(opts, function(x) x$getElementAttribute("value")[[1]])

cat("✅ 크롤링할 회차 구간 목록:\n")
print(opt_texts)
cat("--------------------------------------------\n")


# --- 4. 역대 모든 회차 크롤링을 위한 이중 반복문 시작 ---

# 바깥쪽 반복문: 회차 구간 순회
for (i in 1:length(opt_values)) {
  current_opt_value <- opt_values[i]
  current_opt_text <- opt_texts[i]
  
  cat(sprintf("--- 🔍 구간 선택: %s (Value: %s) ---\n", current_opt_text, current_opt_value))
  
  # 5️⃣ 특정 구간 선택
  # xpath를 이용해 현재 순회 중인 구간 선택
  xpath_str_comb <- paste0("//select[@id='hdrwComb']/option[@value='", current_opt_value, "']")
  remDr$findElement(using = "xpath", value = xpath_str_comb)$clickElement()
  
  # ⚠️ 구간 변경 후 회차 목록이 로드될 때까지 충분히 대기 (Stale 방지)
  Sys.sleep(2)
  
  # 🔑 Stale Element Error 1차 해결: 구간이 바뀔 때마다 회차 목록을 새로 찾아서 갱신
  webElem_list_options <- remDr$findElements(using = 'css', value = '#dwrNoList option')
  
  # 회차 목록의 'value' (회차 번호)만 추출합니다. 이 값은 DOM이 갱신되어도 변하지 않아 안전합니다.
  all_round_values <- sapply(webElem_list_options, function(x) x$getElementAttribute("value")[[1]])
  
  # 안쪽 반복문: 해당 구간 내의 모든 회차 순회
  # 회차 번호를 기준으로 반복문을 돌립니다.
  for (current_round in all_round_values) {
    
    # 저장할 파일 경로 설정
    file_path <- file.path(save_dir, paste0(current_round, ".html"))
    
    # 중복 방지 (Guardrail)
    if (file.exists(file_path)) {
      cat(sprintf("   ⏩ %s 회차: 파일 존재 (%s), 건너뜀\n", current_round, basename(file_path)))
      next # 다음 회차로 건너뜀
    }
    
    # 6-1. 회차 선택 및 조회
    # 💡 Stale Element Error 2차 해결: 클릭할 요소를 클릭 직전에 다시 찾습니다.
    xpath_str_round <- paste0("//select[@id='dwrNoList']/option[@value='", current_round, "']")
    
    tryCatch({
      # 회차 선택
      remDr$findElement(using = "xpath", value = xpath_str_round)$clickElement()
      
      # "조회" 버튼 클릭 (JavaScript 실행)
      remDr$executeScript("document.getElementById('searchBtn').click();")
      
      # 페이지 로드 대기
      Sys.sleep(1.5) 
      
      # 7️⃣ 현재 페이지 HTML 소스 수집 및 저장
      html_source <- remDr$getPageSource()[[1]]
      html <- read_html(html_source)
      
      # HTML 저장
      write_xml(html, file_path, options = "format")
      
      cat(sprintf("   ✅ %s 회차: 저장 완료 (%s)\n", current_round, basename(file_path)))
      
    }, error = function(e) {
      # 에러 발생 시 로그를 남기고 다음 회차로 이동
      cat(sprintf("   ❌ %s 회차 처리 중 에러 발생: %s\n", current_round, e$message))
      Sys.sleep(3) # 에러 발생 시 잠시 대기 후 재시도 방지
    })
  }
  
  cat(sprintf("--- ✅ 구간 크롤링 완료: %s ---\n\n", current_opt_text))
}

# --- 5. 작업 완료 및 세션 종료 ---
cat("\n============================================\n")
cat("🎉 역대 모든 회차 크롤링 및 저장 작업이 완료되었습니다.\n")

# 작업 완료 후 브라우저 세션 및 드라이버 서버 닫기
remDr$close() 
c_drvr$server$stop()




