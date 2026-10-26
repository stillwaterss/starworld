"""Versioned, idempotent browser audio adapter; native game files stay unchanged."""
import re

def adapt_audio(text, adapters):
    for marker in ['# The browser must receive an actual gesture', '# Keep a native callback alive;']:
        if marker in text:text=text[:text.index(marker)]
    text=re.sub(r'^var _web_meter_time.*\n','',text,flags=re.M)
    text=re.sub(r'\t_web_meter_time \+= delta\n\tif OS.has_feature\("web"\) and _web_meter_time >= 1.0:\n\t\t_web_meter_time = 0.0\n(?:\t\tvar peak_db[^\n]*\n\t\tJavaScriptBridge.eval[^\n]*|\t\t_web_report_audio_samples\(\))\n','',text)
    text=re.sub(r'\tif OS.has_feature\("web"\):\n\t\t_web_sound_callback = JavaScriptBridge.create_callback\(_enable_web_sound\)\n\t\tJavaScriptBridge.get_interface\("window"\).starworldEnableSound = _web_sound_callback\n','',text)
    text=re.sub(r'\tif OS.has_feature\("web"\):player.playback_type = AudioServer.PLAYBACK_TYPE_(?:STREAM|SAMPLE)\n','',text)
    text=text.replace('\tif OS.has_feature("web"):\n\t\t_web_prepare_audio_samples()\n\telse:\n\t\tfor player in music + ambience:\n\t\t\tif player.stream:player.play()', '\tfor player in music + ambience:\n\t\tif player.stream:player.play()')
    text=text.replace('\t\tif OS.has_feature("web"):\n\t\t\tfountain.playback_type=AudioServer.PLAYBACK_TYPE_SAMPLE\n\t\t\tif fountain.stream:AudioServer.register_stream_as_sample(fountain.stream)\n\t\telif fountain.stream:fountain.play()', '\t\tif fountain.stream:fountain.play()')
    text=text.replace('AudioServer.add_bus()', 'AudioServer.add_bus(AudioServer.bus_count)')
    def one(old,new):
        nonlocal text
        if text.count(old)!=1:raise RuntimeError('Review changed Claude audio anchor: '+old[:80])
        text=text.replace(old,new,1)
    one('\tload_settings()', '\tload_settings()\n\tif OS.has_feature("web"):\n\t\t_web_sound_callback = JavaScriptBridge.create_callback(_enable_web_sound)\n\t\tJavaScriptBridge.get_interface("window").starworldEnableSound = _web_sound_callback')
    one('\tplayer.name = id', '\tplayer.name = id\n\tif OS.has_feature("web"):player.playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE')
    one('\tfor player in music + ambience:\n\t\tif player.stream:player.play()', '\tif OS.has_feature("web"):\n\t\t_web_prepare_audio_samples()\n\telse:\n\t\tfor player in music + ambience:\n\t\t\tif player.stream:player.play()')
    one('\t\tif fountain.stream:fountain.play()', '\t\tif OS.has_feature("web"):\n\t\t\tfountain.playback_type=AudioServer.PLAYBACK_TYPE_SAMPLE\n\t\t\tif fountain.stream:AudioServer.register_stream_as_sample(fountain.stream)\n\t\telif fountain.stream:fountain.play()')
    one('func _process(delta: float) -> void:', 'func _process(delta: float) -> void:\n\t_web_meter_time += delta\n\tif OS.has_feature("web") and _web_meter_time >= 1.0:\n\t\t_web_meter_time = 0.0\n\t\t_web_report_audio_samples()')
    return text.rstrip()+'\n\n'+(adapters/'audio_callback.gdinc').read_text('utf8')+'\nvar _web_meter_time := 0.0\n'+(adapters/'audio_samples.gdinc').read_text('utf8')
