layers = 10
row = "0"

while layers > 0:
    print(" " * layers + row)
    row += "00"
    layers -= 1
