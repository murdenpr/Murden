function load_odor_serial_messages
%assumes blanks are connected to the normally open input on the manifold
%
% Every message is 'B' + one byte. The valve module firmware reads 'B' as "set all 8 valves at once":
% each bit of the byte is one valve (1 = open, 0 = closed), so any valve not in the byte is closed.
%
% Messages 1-9 (used by every CueConditioning version):
%   1 = all valves closed, 2-9 = valve 1-8 open alone
%   8 = airpuff pressurize valve (valve 7), 9 = airpuff release valve (valve 8)
%
% Messages 10-18 (used by CC_Ver2): message (9 + n) = message n with the pressurize valve also open.
%   CC_Ver2 opens the pressurize valve during the odor, so it sends these instead of message 8
%   to keep the trial's odor valve open while pressurizing. CueConditioning.m never sends 10-18.

bankBytes     = [0 1 2 4 8 16 32 64 128];                       % Byte for messages 1-9 (one bit per valve)
pressurizeBit = 64;                                             % Bit for the pressurize valve (valve 7)

msgs = cell(1, 18);                                             % 18 messages total
for n = 1:9
    msgs{n}     = ['B', bankBytes(n)];                          % Messages 1-9: unchanged from the original file
    msgs{n + 9} = ['B', bitor(bankBytes(n), pressurizeBit)];    % Messages 10-18: same valves plus the pressurize valve
end

LoadSerialMessages('ValveModule1', msgs);                       % Loads all 18 messages for 'ValveModule1' output actions
