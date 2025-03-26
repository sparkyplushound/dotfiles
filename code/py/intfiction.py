print("It's been 2 years since the virus took over the city, you are the only living person left, it's time to escape.")
print("all you have on you is a map of the city, a knife, a flashlight, and some rations.")

print("Look At Map")
print("Check Rations")
print("Look Around Room")
print("Look Out Window")

while True:
    openingOption = input("what would you like to do?: ")

    if openingOption != "leave room" and openingOption != "look out window" and openingOption != "look at map" and openingOption != "check rations":
        print("that was not an option. please try something else")

    elif openingOption == "look at map":
        print("it's map of the city with an escape route leading from this apartment to the walls quarantining the city once there you'll have to figure out a way to get past the walls")

    elif openingOption == "check rations":
        print("you don't have much food left. a few cans of beans, and a few granola bars is all you have until you can either escape or scavenge for more food")

    elif openingOption == "look out window":
        print("once you look out the window you see the ruins of the city. most buildings are either on fire or falling apart. looking at the street you see hordes of the undead. you'll have to figure out how to maneuver past them if you want to escape the city")

    elif openingOption == "leave room":
        print("you pack up your gear and prepare to escape the city. there's no turning back now.")
        break

input("balls?")
