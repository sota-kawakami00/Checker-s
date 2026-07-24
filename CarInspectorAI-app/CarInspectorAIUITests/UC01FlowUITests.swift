import XCTest

/// UIテスト（08_TEST_PLAN §4）
/// UI-01: UC-01完走 — 新規査定→車両情報→12枚撮影(モック)→AI査定(モック)→確定→PDF
final class UC01FlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Form の Menu スタイル Picker から項目を選ぶ（Button/StaticText の両方に対応）
    private func selectPickerOption(_ app: XCUIApplication, pickerId: String, option: String) {
        let picker = app.buttons[pickerId].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "\(pickerId) が見つからない")
        picker.tap()
        let asButton = app.buttons[option].firstMatch
        if asButton.waitForExistence(timeout: 3) {
            asButton.tap()
            return
        }
        let asText = app.staticTexts[option].firstMatch
        XCTAssertTrue(asText.waitForExistence(timeout: 3), "選択肢 \(option) が見つからない")
        asText.tap()
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testUC01FullFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-signin"]
        app.launch()

        // ホーム（空状態 → 新規査定CTA）
        let emptyCTA = app.buttons["＋ 新規査定"]
        XCTAssertTrue(emptyCTA.waitForExistence(timeout: 10), "ホームの新規査定ボタンが見つからない")
        attachScreenshot(app, name: "02_home_empty")
        emptyCTA.firstMatch.tap()

        // 車両情報入力（SCREEN_VEHICLE_INFO）
        let makerPicker = app.buttons["vehicle.picker.maker"]
        XCTAssertTrue(makerPicker.waitForExistence(timeout: 5), "メーカーPickerが見つからない")

        // 「撮影に進む」は必須未充足で非活性（SCR-VEH-03）
        let proceed = app.buttons["vehicle.proceed"]
        XCTAssertTrue(proceed.exists)
        XCTAssertFalse(proceed.isEnabled, "必須未充足で撮影に進むが活性化している")

        selectPickerOption(app, pickerId: "vehicle.picker.maker", option: "トヨタ")
        selectPickerOption(app, pickerId: "vehicle.picker.model", option: "ヴォクシー")
        selectPickerOption(app, pickerId: "vehicle.picker.year", option: "2021年")
        selectPickerOption(app, pickerId: "vehicle.picker.color", option: "パールホワイト")

        let mileage = app.textFields["vehicle.field.mileage"]
        mileage.tap()
        mileage.typeText("42000")
        // キーボードを閉じる（.scrollDismissesKeyboard(.immediately)）
        app.swipeDown()

        attachScreenshot(app, name: "03_vehicle_info")
        XCTAssertTrue(proceed.isEnabled, "必須充足後も撮影に進むが非活性")
        proceed.tap()

        // 撮影（SCREEN_CAMERA、モックカメラで12アングル）
        let shutter = app.buttons["camera.shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10), "シャッターが見つからない")
        let progress = app.staticTexts["camera.progress"]

        for index in 1...12 {
            XCTAssertTrue(shutter.waitForExistence(timeout: 5))
            // 品質判定完了（次アングルへ進む）まで待機
            let expected = "\(index)/12"
            shutter.tap()
            let predicate = NSPredicate(format: "label == %@", expected)
            let expectation = XCTNSPredicateExpectation(predicate: predicate, object: progress)
            let waitResult = XCTWaiter().wait(for: [expectation], timeout: 10)
            XCTAssertEqual(waitResult, .completed, "\(index)枚目の撮影が完了しない")
            if index == 3 {
                attachScreenshot(app, name: "04_camera_progress")
            }
        }

        // ダメージ撮影セクション → スキップ → AI査定実行（SCR-CAM-01）
        let skip = app.buttons["camera.damage.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5), "ダメージ撮影セクションに遷移しない")
        attachScreenshot(app, name: "05_damage_section")
        skip.tap()

        let submit = app.buttons["camera.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        XCTAssertTrue(submit.isEnabled)
        submit.tap()

        // AI解析中（Running）→ 結果（リスナー受信、NFR-02は60秒以内 / モックは数秒）
        let confirmButton = app.buttons["result.confirm"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 60), "査定結果が表示されない")
        attachScreenshot(app, name: "06_result_reviewing")

        // 価格・内訳が表示されている（FR-501/402）
        XCTAssertTrue(app.staticTexts["査定の内訳"].exists)
        XCTAssertTrue(app.staticTexts["市場比較"].exists)

        // 確定（信頼度94%相当 → BR-03通過）
        XCTAssertTrue(confirmButton.isEnabled, "確定ボタンが非活性")
        confirmButton.tap()

        // 確定後: PDF作成（FR-502）
        let pdfButton = app.buttons["result.pdf"]
        XCTAssertTrue(pdfButton.waitForExistence(timeout: 10), "確定後にPDFボタンが出ない")
        attachScreenshot(app, name: "07_result_confirmed")
        pdfButton.tap()

        // PDF生成後に共有ボタンが出る（FR-503）
        let shareButton = app.buttons["共有"]
        XCTAssertTrue(shareButton.waitForExistence(timeout: 10), "PDF生成後に共有が出ない")
        attachScreenshot(app, name: "08_result_pdf_ready")

        // 完了 → Home へ戻る（02 §4: 確定/PDF共有後）
        let doneButton = app.buttons["result.done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5), "完了ボタンが出ない")
        doneButton.tap()

        // 各タブの表示確認（履歴・ダッシュボード・設定）
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5), "タブバーが表示されない")
        app.tabBars.buttons["履歴"].tap()
        XCTAssertTrue(app.navigationBars["査定履歴"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "09_history")

        app.tabBars.buttons["ダッシュボード"].tap()
        XCTAssertTrue(app.navigationBars["ダッシュボード"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "10_dashboard")

        app.tabBars.buttons["設定"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "11_settings")

        // ホームに確定済み査定が反映されている（SCR-HOME-02相当）
        app.tabBars.buttons["ホーム"].tap()
        XCTAssertTrue(app.staticTexts["最近の確定"].waitForExistence(timeout: 5), "確定済みがホームに出ない")
        attachScreenshot(app, name: "12_home_after_confirm")

        // 履歴に確定済み査定の行がある（FR-601）
        app.tabBars.buttons["履歴"].tap()
        XCTAssertTrue(app.staticTexts["トヨタ ヴォクシー"].firstMatch.waitForExistence(timeout: 5), "履歴に査定が出ない")
    }
}
