class Sticker {
  const Sticker(this.id, this.label);

  final String id;
  final String label;

  String get asset => 'assets/stickers/$id.svg';
}

/// Built-in stickers shipped as SVG assets. Messages store only the id, so
/// every client renders them locally without uploads.
const stickerPack = <Sticker>[
  Sticker('wave', 'Waving hand'),
  Sticker('heart', 'Heart'),
  Sticker('thumbs_up', 'Thumbs up'),
  Sticker('laugh', 'Laughing face'),
  Sticker('party', 'Party popper'),
  Sticker('coffee', 'Coffee cup'),
  Sticker('star', 'Star'),
  Sticker('orbit', 'Orbit planet'),
];

Sticker? stickerById(String? id) {
  for (final sticker in stickerPack) {
    if (sticker.id == id) return sticker;
  }
  return null;
}
