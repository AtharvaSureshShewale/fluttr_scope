// A stand-in for build_runner output. Contains a rule violation that must
// NOT be reported — proves the engine's generated-code exclusion actually
// works, not just that it's documented.
void generatedFunction() {
  print('should be excluded from analysis');
}
