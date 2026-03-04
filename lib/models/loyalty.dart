class Loyalty {
  int completed = 0; // Anzahl abgeschlossener Wäschen
  final int goal = 10; // Ziel für Gratis-Wäsche

  double get progress => completed / goal;
}
