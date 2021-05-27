import 'package:flutter/material.dart';
import 'package:hello/hello.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: HelloStringPage(),
    );
  }
}

class HelloStringPage extends StatefulWidget {
  HelloStringPage({Key? key}) : super(key: key);

  @override
  _HelloStringState createState() => _HelloStringState();
}

class _HelloStringState extends State<HelloStringPage> {
  int _counter = 0;
  final Hello hello = Hello();

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Hello plugin example'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            FutureBuilder<String>(
              future: hello.helloString,
              builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
                if (snapshot.hasData) {
                  return Text('${snapshot.data}_$_counter');
                } else if (snapshot.hasError) {
                  return Text('Could not run plugin: ${snapshot.error.toString()}');
                } else {
                  return Text('making hello string');
                }
              },
            ),
            ElevatedButton(
              onPressed: _incrementCounter,
              child: Text('counter add'),
            ),
          ],
        ),
      ),
    );
  }
}
