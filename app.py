from flask import Flask, request, jsonify, render_template
import os

app = Flask(__name__)
LED_PATH = "/sys/class/leds/blue:power"

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/toggle', methods=['POST'])
def toggle():
    try:
        with open(f"{LED_PATH}/brightness", 'r+') as f:
            current = int(f.read())
            f.seek(0)
            f.write('0' if current else '1')
        return jsonify(success=True)
    except Exception as e:
        return jsonify(error=str(e)), 500

@app.route('/set_mode', methods=['POST'])
def set_mode():
    try:
        mode = request.json.get('mode')
        with open(f"{LED_PATH}/trigger", 'w') as f:
            f.write(mode)
        return jsonify(success=True)
    except Exception as e:
        return jsonify(error=str(e)), 500

@app.route('/status')
def status():
    try:
        with open(f"{LED_PATH}/brightness", 'r') as f:
            on = int(f.read()) == 1
        return jsonify(on=on)
    except Exception as e:
        return jsonify(error=str(e)), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)