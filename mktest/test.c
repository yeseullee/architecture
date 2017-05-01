int one();
int two();

int main(int argc, char* argv[]) {
  int c = one()+two();
  return c;
}

int one() {
  return 1;
}
 
int two() {
  return 2;
}
