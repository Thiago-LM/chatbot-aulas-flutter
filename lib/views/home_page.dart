import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:sound_stream/sound_stream.dart';
import 'package:google_speech/google_speech.dart';
import 'package:flutter_dialogflow/dialogflow_v2.dart';

import 'package:dialogflow_chatbot/models/chat_message.dart';
import 'package:dialogflow_chatbot/widgets/chat_message_list_item.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final flutterTts = FlutterTts();
  final _recorder = RecorderStream();
  final _messageList = <ChatMessage>[];
  final _controllerText = new TextEditingController();

  double rate = 1.0;
  double pitch = 1.0;
  double volume = 1.0;
  bool recognizing = false;
  bool recognizeFinished = false;

  Future _setPortugueseBrazilian() async {
    await flutterTts.setLanguage("pt-BR");
  }

  Future _getEngines() async {
    var engines = await flutterTts.getEngines;
    if (engines != null) {
      for (dynamic engine in engines) {
        print(' FlutterTts Engines: ' + engine);
      }
    }
  }

  Future _speak(String text) async {
    await flutterTts.setVolume(volume);
    await flutterTts.setSpeechRate(rate);
    await flutterTts.setPitch(pitch);

    if (text != null && text.isNotEmpty) {
      await flutterTts.speak(text);
    }
  }

  Future _stop() async {
    await flutterTts.stop();
  }

  @override
  void initState() {
    super.initState();

    _getEngines();
    _setPortugueseBrazilian();
    _recorder.initialize().whenComplete(() => streamingRecognize());
    _controllerText.addListener(() {
      print(' _controllerText.text = ' + _controllerText.text);
    });
  }

  void streamingRecognize() async {
    await _recorder.start();

    setState(() {
      recognizing = true;
    });

    final serviceAccount = ServiceAccount.fromString(
        '${(await rootBundle.loadString('assets/credentials.json'))}');
    final speechToText = SpeechToText.viaServiceAccount(serviceAccount);
    final config = _getConfig();

    final responseStream = speechToText.streamingRecognize(
        StreamingRecognitionConfig(config: config, interimResults: true),
        _recorder.audioStream);

    responseStream.listen((data) {
      setState(() {
        _controllerText.text =
            data.results.map((e) => e.alternatives.first.transcript).join('\n');
        recognizeFinished = true;
      });
    }, onDone: () {
      setState(() {
        recognizing = false;
      });
    });
  }

  void stopRecording() async {
    setState(() {
      recognizing = false;
    });
    await _recorder
        .stop()
        .then((_) => _sendMessage(text: _controllerText.text));
  }

  RecognitionConfig _getConfig() => RecognitionConfig(
      encoding: AudioEncoding.LINEAR16,
      model: RecognitionModel.basic,
      enableAutomaticPunctuation: true,
      sampleRateHertz: 16000,
      languageCode: 'pt-BR');

  @override
  void dispose() {
    super.dispose();

    _stop();
    stopRecording();
    _controllerText.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Chatbot - Dialogflow')),
      body: Column(
        children: <Widget>[
          _buildList(),
          Divider(height: 1.0),
          _buildUserInput(),
        ],
      ),
    );
  }

  // Cria a lista de mensagens (de baixo para cima)
  Widget _buildList() {
    return Flexible(
      child: ListView.builder(
        padding: EdgeInsets.all(8.0),
        reverse: true,
        itemBuilder: (_, int index) =>
            ChatMessageListItem(chatMessage: _messageList[index]),
        itemCount: _messageList.length,
      ),
    );
  }

  Future _dialogFlowRequest({String query}) async {
    // Adiciona uma mensagem temporária na lista
    _addMessage(
        name: 'Dialogflow',
        text: 'Escrevendo...',
        type: ChatMessageType.received);

    // Faz a autenticação com o serviço, envia a mensagem e recebe uma resposta da Intent
    AuthGoogle authGoogle =
        await AuthGoogle(fileJson: "assets/credentials.json").build();
    Dialogflow dialogflow =
        Dialogflow(authGoogle: authGoogle, language: "pt-BR");
    AIResponse response = await dialogflow.detectIntent(query);

    // remove a mensagem temporária
    setState(() {
      _messageList.removeAt(0);
    });

    // adiciona a mensagem com a resposta do DialogFlow
    _addMessage(
        name: 'Dialogflow',
        text: response.getMessage() ?? '',
        type: ChatMessageType.received);

    // Reproduz a resposta em forma de áudio
    _speak(response.getMessage());
  }

  // Envia uma mensagem com o padrão a direita
  void _sendMessage({String text}) {
    if (text.isNotEmpty) {
      _controllerText.clear();
      _addMessage(name: 'Usuário', text: text, type: ChatMessageType.sent);
    }
  }

  // Adiciona uma mensagem na lista de mensagens
  void _addMessage({String name, String text, ChatMessageType type}) {
    var message = ChatMessage(text: text, name: name, type: type);
    setState(() {
      _messageList.insert(0, message);
    });

    if (type == ChatMessageType.sent) {
      // Envia a mensagem para o chatbot e aguarda sua resposta
      _dialogFlowRequest(query: message.text);
    }
  }

  // Campo para escrever a mensagem
  Widget _buildTextField() {
    return Flexible(
      child: TextField(
        controller: _controllerText,
        decoration: InputDecoration.collapsed(
          hintText: 'Enviar mensagem',
        ),
      ),
    );
  }

  // Botão para inserir o texto via áudio
  Widget _buildVoiceButton() {
    return Container(
      margin: EdgeInsets.only(left: 8.0),
      child: IconButton(
        icon: recognizing
            ? Icon(Icons.stop, color: Colors.red)
            : Icon(Icons.mic, color: Theme.of(context).accentColor),
        onPressed: recognizing ? stopRecording : streamingRecognize,
      ),
    );
  }

  // Botão para enviar a mensagem
  Widget _buildSendButton() {
    return Container(
      margin: EdgeInsets.only(left: 8.0),
      child: IconButton(
          icon: Icon(Icons.send, color: Theme.of(context).accentColor),
          onPressed: () => _sendMessage(text: _controllerText.text)),
    );
  }

  // Monta uma linha com o campo de text e o botão de enviao
  Widget _buildUserInput() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        children: <Widget>[
          _buildTextField(),
          _buildVoiceButton(),
          _buildSendButton(),
        ],
      ),
    );
  }
}
