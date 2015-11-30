configureSSEP;

% make the stimulus
fig=figure(2);
set(fig,'Name','SSEP Stimulus','color',[0 0 0],'menubar','none','toolbar','none','doublebuffer','on');
clf;
ax=axes('position',[0.025 0.025 .95 .95],'units','normalized','visible','off','box','off',...
        'xtick',[],'xticklabelmode','manual','ytick',[],'yticklabelmode','manual',...
        'color',[0 0 0],'DrawMode','fast','nextplot','replacechildren',...
        'xlim',[-1 1],'ylim',[-1 1],'Ydir','normal');
set(ax,'visible','off');
h=[];
theta=linspace(0,2*pi*(nSymbs-1)/nSymbs,nSymbs); 
for stimi=1:nSymbs;
  h(stimi) =rectangle('curvature',[0 0],'facecolor',bgColor,...
                      'position',[[cos(theta(stimi));sin(theta(stimi))]*.75-stimRadius/2;stimRadius*[1;1]]); 
end
% add the fixation point
h(nSymbs+1) =rectangle('curvature',[1 1],'position',[[0;0]-.5/4;.5/2*[1;1]],'facecolor',bgColor');

% add a txt handle for instructions
txth=text(mean(get(ax,'xlim')),mean(get(ax,'ylim')),' ','HorizontalAlignment','center','VerticalAlignment','middle','color',[0 1 0],'fontunits','normalized','FontSize',.05,'visible','on','interpreter','none');

% show instructions & wait to start
set(txth,'string',feedbackinstructstr,'visible','on');
drawnow;
waitforbuttonpress;
set(txth,'visible','off');

% start the stimulus
state=buffer('poll'); % set initial config
tgt=ones(4,1);
sendEvent('stimulus.testing','start'); 
for seqi=1:seqLen;
    
    if ( ~ishandle(fig) ) break; end;  
    
    sleepSec(intertrialDuration);

    % show the screen to alert the subject to trial start
    set(h(1:end-1),'visible','off');
    set(h(end),'visible','on','facecolor',fixColor); % red fixation indicates trial about to start/baseline
    drawnow;% expose; % N.B. needs a full drawnow for some reason
    sendEvent('stimulus.baseline','start');
    sleepSec(baselineDuration);
    sendEvent('stimulus.baseline','end');  
        
    % make the stim-seq for this trial
    [stimSeq,stimTime,eventSeq,colors]=mkStimSeqSSEP(h,trialDuration,isi,periods,false);

										  % now play the sequence
    ev=sendEvent('stimulus.trial','start');
	 sendEvent('classifier.apply','now',ev.sample);%tell the classifier to apply to this data
	 evti=0; stimEvts=mkEvent('test'); % reset the total set of events info
    seqStartTime=getwTime(); ei=0; ndropped=0; frametime=zeros(numel(stimTime),4);
    while ( stimTime(end)>=getwTime()-seqStartTime ) % frame-dropping version    

		% get the next frame to display -- dropping frames if we're running slow
      ei=min(numel(stimTime),ei+1);
      frametime(ei,1)=getwTime()-seqStartTime;
      % find nearest stim-time, dropping frames is necessary to say on the time-line
      if ( frametime(ei,1)>=stimTime(min(numel(stimTime),ei+1)) ) 
        oei = ei;
        for ei=ei+1:numel(stimTime); if ( frametime(oei,1)<stimTime(ei) ) break; end; end; % find next valid frame
        if ( verb>=0 ) fprintf('%d) Dropped %d Frame(s)!!!\n',ei,ei-oei); end;
        ndropped=ndropped+(ei-oei);
      end


		% update the display with the current frame's information
		set(h(:),'facecolor',bgColor); % everybody starts as background color
      ss=stimSeq(:,ei);
      set(h(ss<0),'visible','off');  % neg stimSeq codes for invisible stimulus
      set(h(ss>=0),'visible','on');  % positive are visible    
      if(any(ss==1))set(h(ss==1),'facecolor',colors(:,1)); end;% stimSeq codes into a colortable
      if(any(ss==2))set(h(ss==2),'facecolor',colors(:,min(size(colors,2),2)));end;
      if(any(ss==3))set(h(ss==3),'facecolor',colors(:,min(size(colors,2),3)));end;

      % sleep until time to re-draw the screen
      sleepSec(max(0,stimTime(ei)-(getwTime()-seqStartTime))); % wait until time to call the draw-now
      if ( verb>0 ) frametime(ei,2)=getwTime()-seqStartTime; end;
      drawnow;
      if ( verb>0 ) 
        frametime(ei,3)=getwTime()-seqStartTime;
        fprintf('%d) dStart=%8.6f dEnd=%8.6f stim=[%s] lag=%g\n',ei,...
                frametime(ei,2),frametime(ei,3),...
                sprintf('%d ',stimSeq(:,ei)),stimTime(ei)-(getwTime()-seqStartTime));
      end

      % record event info about this stimulus to send later so don't delay stimulus
	   if ( isempty(eventSeq) || (numel(eventSeq)>ei && eventSeq(ei)>0) )
		  samp=buffer('get_samp'); % get sample at which display updated
		  % event with information on the total stimulus state
		  evti=evti+1; stimEvts(evti)=mkEvent('stimulus.stimState',ss,samp); 
		end

    end % while < endTime
    if ( verb>0 ) % summary info
      dt=frametime(:,3)-frametime(:,2);
      fprintf('Sum: %d dropped frametime=%g drawTime=[%g,%g,%g]\n',...
              ndropped,mean(diff(frametime(:,1))),min(dt),mean(dt),max(dt));
    end
    
    % reset the cue and fixation point to indicate trial has finished  
    set(h(:),'facecolor',bgColor);
    drawnow;
	 sendEvent('stimulus.trial','end');

	 % wait for any prediction events
	 % wait for classifier prediction event
	 if( verb>0 ) fprintf(1,'Waiting for predictions\n'); end;
	 [devents,state]=buffer_newevents(buffhost,buffport,state,'classifier.prediction',[],500);  

	 % do something with the prediction (if there is one), i.e. give feedback
	 if( isempty(devents) ) % extract the decision value
		fprintf(1,'Error! no predictions, continuing');
	 else
		dv = devents(end).value;
		if ( numel(dv)==1 )
        if ( dv>0 && dv<=nSymbs && isinteger(dv) ) % dvicted symbol, convert to dv equivalent
			 tmp=dv; dv=zeros(nSymbs,1); dv(tmp)=1;
        else % binary problem, convert to per-class
			 dv=[dv -dv];
        end
		end
		% give the feedback on the predicted class
		prob=1./(1+exp(-dv)); prob=prob./sum(prob);
		if ( verb>=0 ) 
        fprintf('dv:');fprintf('%5.4f ',dv);fprintf('\t\tProb:');fprintf('%5.4f ',prob);fprintf('\n'); 
		end;  
		[ans,predTgt]=max(dv); % prediction is max classifier output
		set(h(:),'facecolor',bgColor);
		set(h(predTgt),'facecolor',feedbackColor);
		drawnow;
		sendEvent('stimulus.predTgt',predTgt);
	 end % if classifier prediction
	 sleepSec(feedbackDuration);
	 
    % reset the cue and fixation point to indicate trial has finished  
    set(h(:),'facecolor',bgColor,'visible','off');
    drawnow;
    
    fprintf('\n');
end % sequences

% end training marker
sendEvent('stimulus.testing','end');

% thanks message
if ( ishandle(fig) && ishandle(txth) )
  set(txth,'string',thanksstr,'visible','on');
  drawnow;
  pause(3);
  close(fig)
end
