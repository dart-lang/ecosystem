// TODO: Put public facing types in this file.

/// Checks if you are awesome. Spoiler: you are.
class Awesome {
  bool get isAwesome => true;

  NonExported get myClass => NonExported();
  NonExported2 get myClass2 => NonExported2();
}

class NonExported {}

class NonExported2 {
  TransitiveNonExported get myClass => TransitiveNonExported();
}

class TransitiveNonExported {}
