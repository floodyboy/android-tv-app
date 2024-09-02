import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mawaqit/src/data/data_source/quran/recite_remote_data_source.dart';
import 'package:mawaqit/src/data/data_source/quran/reciter_local_data_source.dart';

import 'package:mawaqit/src/domain/model/quran/reciter_model.dart';

import 'package:mawaqit/src/domain/repository/quran/recite_repository.dart';

class ReciteImpl implements ReciteRepository {
  final ReciteRemoteDataSource _remoteDataSource;
  final ReciteLocalDataSource _localDataSource;

  ReciteImpl(this._remoteDataSource, this._localDataSource);

  @override
  Future<List<ReciterModel>> getAllReciters({required String language}) async {
    try {
      final reciters = await _remoteDataSource.getReciters(language: language);
      reciters.sort((a, b) => a.name.compareTo(b.name));
      await _localDataSource.saveReciters(reciters);
      return reciters;
    } catch (e) {
      final reciters = await _localDataSource.getReciters();
      reciters.sort((a, b) => a.name.compareTo(b.name));
      return reciters;
    }
  }
}

final reciteImplProvider = FutureProvider<ReciteImpl>((ref) async {
  final remoteDataSource = ref.read(reciteRemoteDataSourceProvider);
  final localDataSource = await ref.read(reciteLocalDataSourceProvider.future);
  return ReciteImpl(remoteDataSource, localDataSource);
});
