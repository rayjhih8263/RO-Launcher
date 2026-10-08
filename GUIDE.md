# 啟動器設定與更新發布

## 目前狀態
公告介面與 rpatchur 0.3.x 設定已準備。GitHub Pages 需要啟用，Windows 實機與首個 THOR 更新包尚待測試。更新清單目前為空，不能據此認定 Client 檔案完整。

## 1. 啟用公告頁
Repository Settings → Pages → Build and deployment：
- Source：Deploy from a branch
- Branch：main
- Folder：/docs
- Save

部署完成後開啟 https://rayjhih8263.github.io/RO-Launcher/ 。

## 2. 準備 Windows 啟動器
從 https://github.com/L1nkZ/rpatchur/releases 下載 0.3.x 的 Windows 程式，解壓後將 rpatchur.exe 改名為 RO-Launcher.exe。
下載本專案 launcher/RO-Launcher.yml，與 EXE 一起放在 RO Client 根目錄。
必須與 2021-11-03_Ragexe_patched.exe、Setup_Plus.exe 在同一目錄。
若遊戲 EXE 不同，修改設定中的 play.path。
play.arguments 使用官方範例的 1sak1，實測時需核對目前 Client 的啟動參數。
首次在完整 Client 副本測試，確認公告、更新檢查、Setup 及登入正常。

## 3. 修改公告
編輯 docs/index.html 的公告 article 區塊後提交。Pages 部署完成後玩家重開啟動器即可讀取。
保留更新狀態、按鈕、JavaScript callbacks 與 external.invoke 呼叫。

## 4. 建立首個更新包
使用 GRF Editor 或 rpatchur 的 mkpatch 製作 THOR 包；不要直接將 ZIP 改副檔名。
先用無害的測試文字檔，以「Client 資料夾檔案」模式更新到 launcher-test.txt，不要改帳號與連線設定。
若是 GRF 更新，需明確核對目標 GRF、內部路徑、DATA.INI 載入順序與 data 資料夾覆蓋優先順序。
目前設定預設 GRF 為 data.grf，禁止自動建立缺少的 GRF；沒有核對前不要發布 GRF 更新。
更新包应包含完整性檢查資訊，並保持 check_integrity: true。

## 5. 發布更新
1. 用 Client 副本測試更新包。
2. 在 GitHub Releases 建立 tag 為 patches 的固定發行版本（標題可用「Client 更新包」）。
3. 上傳獨特且不再變更的檔名，例如 0001-test.thor。
4. 確認以下下載網址可取得檔案：
   https://github.com/rayjhih8263/RO-Launcher/releases/download/patches/0001-test.thor
5. 最後在 docs/plist.txt 加入一行（編號、空格、檔名）：
   1 0001-test.thor
6. 等待 Pages 部署，再從未套用此包的 Client 副本測試下載、套用及第二次啟動不重複更新。
7. 檢查測試檔後，才開始製作正式更新。

後續依序加入 2、3 等編號。保留所有舊清單與舊包，不改已發布包；修正要發布新編號，避免玩家版本不一致。
Releases 的 patches tag 必須與設定檔 patch_url 一致。
公告頁發布與 Releases 上傳不會自動替你製作更新包。

## 6. 更新與修復的區別
check_integrity 檢查 THOR 更新包；不會掃描完整 Client 或自動修復所有 GRF。
不要刪除更新器快取強制重套來代替完整修復，也不要更新正在執行的遊戲檔案。

## 上游文件
- https://l1nkz.github.io/rpatchur/
- https://github.com/L1nkZ/rpatchur/blob/master/examples/rpatchur.yml
- https://github.com/L1nkZ/rpatchur/releases
