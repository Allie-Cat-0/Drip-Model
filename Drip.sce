/*
**    Scliab script to model Drip Network sustainability
**    Author: Allissa Auld (https://medium.com/@allissa.auld)
**    For article and disclaimer ralating to the script see 
*/

/////////////////////Begin Monte-Carlo Loop/////////////////////////
clear() //clears all existing variables
//set overall simulation variables
Monte = 5  //number of simulations
NumWallets = 10000 //Define number of wallets to simulate
Days = 365*6 //Define number of days to simulate (6 years)
//set model variables
InitVault = 600000 //set initial vault balance
AvInit = 55 //set the average for the wallet exponential distribution (approximation based on BscScan deposits)
Chance = 2 //% chance a given wallet starts on a given day
Vault=zeros(Monte,Days) //initialise vault matrix
Minted=zeros(Monte,Days) //initialise minted matrix
//Set whale tax matrix
Whale =         [0.0099, 0.00;
                0.01, 0.05;
                0.02, 0.10;
                0.03, 0.15;
                0.04, 0.20;
                0.05, 0.25;
                0.06, 0.30;
                0.07, 0.35;
                0.08, 0.40;
                0.09, 0.45;
                0.10, 0.50]
//Define different strategies for managing the wallet
//Ideal strategies based on work by Kelly Snook at https://cryptozoa.com/dripping-with-confidence-simple-rules-for-success-with-drip-part-1-7e3070c18ae7
Strategies =    ["Nothing"; 
                "Claim Only"; 
                "Ideal"; 
                "Ideal Alternating"
                "Hydrate Only"; 
                "Random"]
x=1 //initialise Monte-Carlo run variable
for x = 1:Monte, //enters Monte-Carlo loop and clears simulation run variables
    if exists("Claimed","n") == 1 then
        clear("Claimed")
    elseif exists("MaxPayout","n") == 1 then
        clear("MaxPayout")
    elseif exists("WhaleTax","n") == 1 then
        clear("WhaleTax")
    elseif exists("Available","n") == 1 then
        clear("Available")
    elseif exists("StratType","n") == 1 then
        clear("StratType")
    elseif exists("DailyStrat","n") == 1 then
        clear("DailyStrat")
    elseif exists("Start","n") == 1 then
        clear("Start")
    elseif exists("Initial","n") == 1 then
        clear("Initial")
    elseif exists("Deposits","n") == 1 then
        clear("Deposits")
    elseif exists("TotalSupply","n") == 1 then
        clear("TotalSupply")
    elseif exists("TaxLimit","n") == 1 then
        clear("TaxLimit")
    end,

//////////////////Initialise loop simulation variables//////////////
    Claimed=zeros(NumWallets,Days) //initialise claims matrix
    Deposits=zeros(NumWallets,Days) //initialise deposits matrix
    MaxPayout=zeros(NumWallets,Days) //initialise max payout matrix
    WhaleTax=zeros(NumWallets,Days) //initialise whale tax matrix
    AvailablePre=zeros(NumWallets,Days) //initialise available pre-daily action matrix
    AvailablePost=zeros(NumWallets,Days) //initialise available post-daily action matrix
    Vault(x,1) = InitVault //set initial vault balance for this run
    //Set frequency of each strategy (estimated)
    StratFreq =     [1; 
                    4; 
                    3;
                    4; 
                    3; 
                    5]

////////////////////////////Set Strategy////////////////////////////
    //Establish each wallet strategy based on frequency
    seed = getdate("s") //sets seed to the POSIX timestamp
    seed = int(seed) //makes seed an integer
    grand("setsd", seed) //sets the random seed generator to the POSIX time, this helps create a more random variation
    StratType = samplef(NumWallets, Strategies, StratFreq,'r')
    //Set Strategy actions inside matrix
    for i = 1:NumWallets, //strategy action is 0 = nothing, 1 = claim, 2 = hydrate
        if StratType(i) == "Nothing" then
            for j = 1:Days,
                DailyStrat(i,j) = 0; //set every day to do nothing
            end,
        elseif StratType(i) == "Claim Only" then
            for j = 1:Days,
                DailyStrat(i,j) = 1; //set every day to claim
            end,
        elseif StratType(i) == "Ideal" then //Hydrate every day until 27300 drip (set to hydrate only, adjust max later)
            for j = 1:Days,
                DailyStrat(i,j) = 2;
        end,
        elseif StratType(i) == "Ideal Alternating" then //Alternating Hydrate and claims until 27300 drips
            for j = 1:2:Days,
                DailyStrat(i,j) = 2; //set odds to hydrate
        end,
            for j = 2:2:Days,
                DailyStrat(i,j) = 1; //set evens to claim
        end,
        elseif StratType(i) == "Hydrate Only" then
            for j = 1:Days,
                DailyStrat(i,j) = 2; //set every day to hydrate
        end,
        elseif StratType(i) == "Random" then
            for j = 1:Days,
                k = grand(1, Days, "def") //set a random uniform matrix
                if k(j) < 0.33 then //one randomised third of days do nothing
                    DailyStrat(i,j) = 0;
                end,
                if k(j) >= 0.33 & k(j) <= 0.66 then //one randomised third of days claim
                    DailyStrat(i,j) = 1;
                end,
                if k(j) > 0.66 then //one randomised third of days hydrate 
                    DailyStrat(i,j) = 2;
                end,
            end,
        end,
    end,

/////////////////////////////Set Deposits///////////////////////////
    Initial = grand(NumWallets, 1, "exp", AvInit) //set initial wallet balance based on exponential distribution from 1 with average AvInit drip deposit
    for i = 1:NumWallets,
        if Initial(i) < 1.1 then //checks if initial deposit would be less than minimum of 1.0, if so increases to 1.1 to make initial deposit 1.0 (after tax)
            Initial(i) = 1.1
        end,
    end,
    //now we'll use a random matrix to pick the starting day of each wallet
    Start = grand(NumWallets, Days, "def") //set random matrix
    for i = 1:NumWallets,
        for j = 1:Days,
            if sum(Start(i,1:(j-1))) ~= 1 then //check if wallet has already started
                if Start(i,j) < (1-(Chance/100)) then //set chance a wallet does not start on a given day
                    Start(i,j) = 0
                elseif Start(i,j) >= (1-(Chance/100)) then //set chance a wallet starts on a given day
                    Start(i,j) = 1
                end,
            else Start(i,j) = 0 //if wallet started it does noting
            end,
        end,
    end,

////////////////////////Initialise Wallets/////////////////////////
    //Set initial wallet balances
    for i=1:NumWallets,
        for j=1,
            Deposits(i,j) = Initial(i)*Start(i,j) //if the wallet has started on day 1 then put initial amount it
        end,
    end,

//////////////////////Daily Wallet Calculations///////////////////
    //Now vary each wallet balance based on daily strategy
    for i = 1:NumWallets, //cycle through all wallets
        for j = 2:Days, //start on day 2 since day 1 is only initial deposits

            AvailablePre(i,j) = AvailablePost(i,(j-1)) + Deposits(i,(j-1))*0.01 //available is amount from previous day after wallet actions plus 1% of previous day's deposit balance

            //check if ideal strategies have reached ideal claiming numbers (>27397 drip deposited) and if so then claim
            if StratType(i) == "Ideal" then //if strategy is ideal
                if Deposits(i,(j-1)) > (100000/3.65) then //if reached approx 27,397 drips (which means 3.65% is 100,000 which is max payout)
                    DailyStrat(i,j) = 1 //tell strategy to claim regardless of preset
                end,
            elseif StratType(i) == "Ideal Alternating" then //if strategy is ideal alternating
                if Deposits(i,(j-1)) > (100000/3.65) then //if reached approx 27,397 drips (which means 3.65% is 100,000 which is max payout)
                    DailyStrat(i,j) = 1 //tell strategy to claim regardless of preset
                end,
            end,
            //check for whale tax
            if Vault(x,(j-1)) < 1000000 then //check if total supply less than 1,000,000
                TotalSupply(j) = 1000000 //total supply never less than 1,000,000 since that's the initial minted amount
            else TotalSupply(j) = TotalSupply(j-1) + Minted(x,(j-1)) //increases TotalSupply if more Drip is minted.
            end,
            m=1 //initialise whale tax variable
            for m = 1:11, //starts loop to check for whale tax
                TaxLimit = TotalSupply(j)*Whale(m,1) //checks each whale tax level 
                if (Claimed(i,(j-1)) + AvailablePre(i,j)) > TaxLimit then //check whale status against Claims + Available
                    WhaleTax(i,j) = Whale(m,2) //set whale tax
                end,
            end,
            //start daily actions
            z=0 //zero wallet action variable (0 no action, 1 action has occurred today)
            if Start(i,j) == 1 then //check for newly-active wallets
                Vault(x,j) = Vault(x,(j-1)) + Initial(i) //add initial deposit to the Vault
                Deposits(i,j) = Initial(i) //add initial deposit to Deposits
            
            elseif Claimed(i,(j-1)) >= MaxPayout(i,(j-1)) then //check if max payout has been reached
                AvailablePre(i,j) = 0 //kill the wallet (no more available)
                DailyStrat(i,j) = 0 //tell strategy to do nothing regardless of preset
                Claimed(i,j) = Claimed(i,(j-1)) // claimed stays the same due no action
                Deposits(i,j) = Deposits(i,(j-1)) //no change to deposits
                Vault(x,j) = Vault(x,(j-1)) //no change to vault
                // this method below gives a wallet a probability to be restarted, simulating a new player to the network.
                if grand("def") > (1-(Chance/100)) //set probability of wallet starting
                    Vault(x,j) = Vault(x,(j-1)) + Initial(i) //add initial deposit to the Vault
                    Deposits(i,j) = Initial(i) //reset Deposits to initial deposit
                    AvailablePre(i,j) = 0 //zeroise this wallet's available
                    Claimed(i,j) = 0 //zeroise this wallet's claims
                    MaxPayout(i,j) = 0 //zeroise max payout
                    AvailablePost(i,j) = 0 //zeroise available post action
                end,

            else //now we enter the strategy calculations

                if DailyStrat(i,j) == 0 then //strategy says do nothing on this day
                    Deposits(i,j) = Deposits(i,(j-1)) //Deposits stays the same due no action
                    AvailablePost(i,j) = AvailablePre(i,j) //Available stays the same due no action
                    Claimed(i,j) = Claimed(i,(j-1)) //Claimed stays the same due no action
                    Vault(x,j) = Vault(x,(j-1)) //Vault stays the same due no action
                    z=1 //set wallet action occurred to yes (even though this strategy did nothing)
                            
                elseif DailyStrat(i,j) == 1 then //strategy says claim on this day
                    Deposits(i,j) = Deposits(i,(j-1)) + 0 //deposits remains the same due claiming
                    Vault(x,j) = (Vault(x,(j-1)) - AvailablePre(i,j)) + (AvailablePre(i,j)*0.1) + (AvailablePre(i,j)*WhaleTax(i,j)) // pay reward from vault, then put 10% tax back in, charge whale tax if required
                    Claimed(i,j) = Claimed(i,(j-1)) + AvailablePre(i,j) //add claimed to claimed drip tracker
                    Vault(x,j) = Vault(x,j) + (((AvailablePre(i,j)*((1-WhaleTax(i,j))*0.9)))*0.1) //assume claimed is sold after claim (it likely would at some point and the timing does not impact the model) and put 10% of the sold (which is 90% of available after whale tax) into the vault
                    AvailablePost(i,j) = 0 //zero available since claimed
                    z=1 //set wallet action occurred to yes

                elseif DailyStrat(i,j) == 2 then //strategy says hydrate on this day
                    Deposits(i,j) = Deposits(i,(j-1)) + (AvailablePre(i,j)*0.95) //add hydrated amount to wallet deposits - 5% tax
                    Vault(x,j) = Vault(x,(j-1)) + AvailablePre(i,j) //put hydrated amount back in vault
                    Claimed(i,j) = Claimed(i,(j-1)) + AvailablePre(i,j) //add claimed to claimed tracker
                    AvailablePost(i,j) = 0 //zero available since claimed
                    z=1 //set wallet action occurred to yes
                end,

                if z == 0 //check for wallet action on this day
                    AvailablePost(i,j) = AvailablePre(i,j) //if no wallet action, the available pre-action and post-action are the same
                end
            end,

            //update max payout based on day's actions
            MaxPayout(i,j) = Deposits(i,j)*3.65 //MaxPayout is 365%*Deposits
            if MaxPayout(i,j) > 100000 then
                MaxPayout(i,j) = 100000 //makes sure max payout of 100,000 drip is not exceeded
            end,
            if AvailablePost(i,j) > 100000 then
                AvailablePost(i,j) = 100000 //makes sure available max payout of 100,000 drip is not exceeded
            end,
            if AvailablePost(i,j) > Deposits(i,j)*3.65 then
                AvailablePost(i,j) = Deposits(i,j)*3.65 //makes sure available max payout of max 365%*deposit is not exceeded
            end,
            if Vault(x,j) < 0 then //check for negative vault balance and mint if required.
                Minted(x,j) = (0-Vault(x,j)) //mint required tokens
                Vault(x,j) = Vault(x,j) + Minted(x,j) //add minted to Vault
            end,
        end,
    end,

////////////////////////End Monte-Carlo Loop////////////////////////
    y = ((x/Monte)*100)
    mprintf("Simulation is %2.3f%% complete\n", y);
end
