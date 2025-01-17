import 'dart:core';
import 'dart:io' as io;
import 'dart:convert';

import 'package:logging/logging.dart';

import 'config.dart';
import 'harvester.dart';
import 'debug.dart' as Debug;

final log = Logger('Farmer');

class Farmer extends Harvester {
  String _status;
  String get status => _status;

  double _balance = 0;
  double get balance => _balance; //hides balance if string

  String _networkSize = "0";
  String get networkSize => _networkSize;

  @override
  ClientType _type = ClientType.Farmer;
  @override
  ClientType get type => _type;

  //SubSlots with 64 signage points
  int _completeSubSlots = 0;
  int get completeSubSlots => _completeSubSlots;

  //Signagepoints in an incomplete sub plot
  int _looseSignagePoints = 0;
  int get looseSignagePoints => _looseSignagePoints;

  @override
  Map toJson() => {
        'name': name,
        'status': status,
        'balance': balance,
        'networkSize': networkSize,
        'plots': allPlots, //important
        'totalDiskSpace': totalDiskSpace,
        'freeDiskSpace': freeDiskSpace,
        'lastUpdated': lastUpdated.millisecondsSinceEpoch,
        'lastUpdatedString': lastUpdatedString,
        'type': type.index,
        'completeSubSlots': completeSubSlots,
        'looseSignagePoints': looseSignagePoints,
        'numberFilters': numberFilters,
        'eligiblePlots': eligiblePlots,
        'proofsFound': proofsFound,
        'totalPlots': totalPlots,
        'missedChallenges': missedChallenges,
        'maxTime': maxTime,
        'minTime': minTime,
        'avgTime': avgTime,
        'medianTime': medianTime,
        'stdDeviation': stdDeviation
      };

  Farmer(Config config, Debug.Log log) : super(config, log) {
    //runs chia farm summary if it is a farmer
    var result = io.Process.runSync(config.cache.binPath, ["farm", "summary"]);
    List<String> lines = result.stdout.toString().replaceAll("\r", "").split('\n');
    try {
      for (int i = 0; i < lines.length; i++) {
        String line = lines[i];

        if (line.startsWith("Total chia farmed: "))
          _balance =
              (config.showBalance) ? double.parse(line.split('Total chia farmed: ')[1]) : -1.0;
        else if (line.startsWith("Farming status: "))
          _status = line.split("Farming status: ")[1];
        else if (line.startsWith("Estimated network space: "))
          _networkSize = line.split("Estimated network space: ")[1];
      }
    } catch (exception) {
      print("Error parsing Farm info.");
    }

    //Parses logs for sub slots info
    if (config.parseLogs) {
      log.loadSignagePoints();
      calculateSubSlots(log);
    }
  }

  //Server side function to read farm from json file
  Farmer.fromJson(String json) : super.fromJson(json) {
    var object = jsonDecode(json)[0];

    _status = object['status'];
    _balance = object['balance'];
    _networkSize = object['networkSize'];

    //PiB to EiB converter
    if (_networkSize.contains("PiB")) {
      double value = double.parse(_networkSize.replaceAll("PiB", "").trim());
      if (value > 1024) {
        value = value / 1024;
        _networkSize = "${value.toStringAsPrecision(3)} EiB";
      }
    }

    if (object['completeSubSlots'] != null) _completeSubSlots = object['completeSubSlots'];
    if (object['looseSignagePoints'] != null) _looseSignagePoints = object['looseSignagePoints'];

    calculateFilterRatio(this);
  }

  //Adds harvester's plots into farm's plots
  void addHarvester(Harvester harvester) {
    allPlots.addAll(harvester.allPlots);

    addHarversterFilters(harvester);

    if (harvester is Farmer) {
      _completeSubSlots += harvester.completeSubSlots;
      _looseSignagePoints += harvester._looseSignagePoints;
    }

    if (harvester.totalDiskSpace == 0 || harvester.freeDiskSpace == 0) supportDiskSpace = false;

    //Adds harvester total and free disk space when merging
    totalDiskSpace += harvester.totalDiskSpace;
    freeDiskSpace += harvester.freeDiskSpace;

    //Disables avg, median, etc. in !chia full
    this.disableDetailedTimeStats();
  }

  void calculateSubSlots(Debug.Log log) {
    _completeSubSlots = log.subSlots.where((point) => point.complete).length;

    var incomplete = log.subSlots.where((point) => !point.complete);
    _looseSignagePoints = 0;
    for (var i in incomplete) {
      _looseSignagePoints += i.signagePoints.length;
    }
  }
}
