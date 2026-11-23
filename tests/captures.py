import sys
from playwright.sync_api import sync_playwright
U = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8000"
with sync_playwright() as p:
    b = p.chromium.launch()
    pg = b.new_page(viewport={"width": 1200, "height": 800})
    erreurs = []
    pg.on("console", lambda m: erreurs.append(m.text) if m.type == "error" else None)
    pg.goto(U + "/"); pg.screenshot(path="/tmp/p1.png", full_page=True)
    pg.goto(U + "/inscription"); pg.screenshot(path="/tmp/p_inscr.png", full_page=True)
    pg.goto(U + "/")
    pg.fill("#pseudo", sys.argv[2]); pg.fill("#mdp", sys.argv[3]); pg.click("button[type=submit]")
    pg.wait_for_url("**/parties"); pg.screenshot(path="/tmp/p2.png", full_page=True)
    m = b.new_page(viewport={"width": 390, "height": 800}); m.goto(U + "/"); m.screenshot(path="/tmp/p1_mobile.png", full_page=True)
    print("erreurs console :", erreurs)
    b.close()
