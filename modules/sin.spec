double result;

void init() {
    result = 0.0;
}

void exec(in signal, out result) {
    {
        result = sin(signal);
    }
}
