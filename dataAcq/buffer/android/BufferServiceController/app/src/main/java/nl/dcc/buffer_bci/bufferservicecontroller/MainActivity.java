package nl.dcc.buffer_bci.bufferservicecontroller;

import android.app.Activity;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Bundle;
import android.view.View;
import android.widget.*;
import nl.dcc.buffer_bci.bufferservicecontroller.visualize.BubbleSurfaceView;
import nl.dcc.buffer_bci.bufferclientsservice.ThreadInfo;
import nl.dcc.buffer_bci.bufferclientsservice.base.Argument;
import nl.dcc.buffer_bci.monitor.BufferConnectionInfo;

import java.util.HashMap;


public class MainActivity extends Activity {

    public static String TAG = MainActivity.class.getSimpleName();

    public ServerController serverController;
    public ClientsController clientsController;

    private BroadcastReceiver mMessageReceiver;

    // Gui
    private TextView textView;
    private LinearLayout table;
    private HashMap<Integer, Integer> threadToView;
    private BubbleSurfaceView surfaceView;

    @Override
    protected void onCreate(final Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        setContentView(R.layout.main_activity);
        textView = (TextView) findViewById(R.id.textView);
        table = (LinearLayout) findViewById(R.id.switches);
        threadToView = new HashMap<Integer, Integer>();
        surfaceView = (BubbleSurfaceView) findViewById(R.id.surfaceView);

        serverController = new ServerController(this);
        if (serverController.isBufferServerServiceRunning()) {// check if already running
            serverController.reloadConnections();
        }
        clientsController = new ClientsController(this);
        if (clientsController.isThreadsServiceRunning()) {// check if already running
            clientsController.reloadAllThreads();
        }

        if (savedInstanceState == null) {
            IntentFilter intentFilter = new IntentFilter(C.FILTER_FROM_SERVER);
            mMessageReceiver = new BroadcastReceiver() {
                @Override
                public void onReceive(final Context context, Intent intent) {
                    updateServerController(intent);
                }
            };
            this.registerReceiver(mMessageReceiver, intentFilter);
        }
    }

    @Override
    public void onStop() {
        super.onStop();
        this.unregisterReceiver(mMessageReceiver);
    }

    @Override
    public void onDestroy() {
        stopClients();
        stopServer();
        super.onDestroy();
    }

    private void updateServerController(Intent intent) {
        if (intent.getBooleanExtra(C.IS_BUFFER_INFO, false)) {
            updateServerInfo(intent);
        }
        if (intent.getBooleanExtra(C.IS_BUFFER_CONNECTION_INFO, false)) {
            updateBufferConnectionInfo(intent);
        }
        if (intent.getBooleanExtra(C.IS_THREAD_INFO, false)) {
            updateThreadsInfo(intent);
        }
    }

    private void updateServerInfo(Intent intent) {
        serverController.buffer = intent.getParcelableExtra(C.BUFFER_INFO);
        if (!serverController.initalUpdateCalled) {
            serverController.initialUpdate();
        }
        serverController.updateBufferInfo();
        this.updateConnectionsGui();
    }

    private void updateBufferConnectionInfo(Intent intent) {
        int numOfClients = intent.getIntExtra(C.BUFFER_CONNECTION_N_INFOS, 0);
        BufferConnectionInfo[] bufferConnectionInfo = new BufferConnectionInfo[numOfClients];
        for (int k = 0; k < numOfClients; ++k) {
            bufferConnectionInfo[k] = intent.getParcelableExtra(C.BUFFER_CONNECTION_INFO + k);
        }
        serverController.updateBufferConnections(bufferConnectionInfo);
        this.updateConnectionsGui();
    }

    private void updateThreadsInfo(Intent intent) {
        ThreadInfo threadInfo = intent.getParcelableExtra(C.THREAD_INFO);
        int nArgs = intent.getIntExtra(C.THREAD_N_ARGUMENTS, 0);
        Argument[] arguments = new Argument[nArgs];
        for (int i = 0; i < nArgs; i++) {
            arguments[i] = (Argument) intent.getSerializableExtra(C.THREAD_ARGUMENTS + i);
        }
        clientsController.updateThreadInfoAndArguments(threadInfo, arguments);
        this.updateClientsGui();
    }

    // Gui
    private void updateConnectionsGui(){
        textView.setText(serverController.toString());
    }

    private void updateClientsGui() {
        int[] threadIDs = clientsController.getAllThreadIDs();
        if (threadIDs.length < 1) {
            table.removeViews(2, threadToView.size());
            threadToView.clear();
        }
        int newIndex = table.getChildCount();
        for (int threadID : threadIDs) {
            if (!threadToView.containsKey(threadID)) {
                String title = clientsController.getThreadTitle(threadID);
                Switch newSwitch = new Switch(this);
                newSwitch.setText(title);
                newSwitch.setOnClickListener(getThreadStarter(threadID));
                table.addView(newSwitch, newIndex);
                threadToView.put(threadID, newIndex);
                newIndex++;
            }
        }
    }

    private View.OnClickListener getThreadStarter(final int threadID) {
        return new View.OnClickListener() {
            @Override
            public void onClick(View view) {
                Switch switchView = (Switch) view;
                if (switchView.isChecked())
                    clientsController.startThread(threadID);
                else
                    clientsController.stopThread(threadID);
            }
        };
    }

    //Interface
    public void startServer() {
        String serverName = "";
        if (!serverController.isBufferServerServiceRunning()) {
            serverName = serverController.startServerService();
        } else {
            serverController.reloadConnections();
        }
    }

    public void startClients() {
        String clientsName = "";
        if (!clientsController.isThreadsServiceRunning()) {
            clientsName = clientsController.startThreadsService();
        } else { // query for the threads info
            clientsController.reloadAllThreads();
        }
        updateClientsGui();
    }

    public void stopServer() {
        boolean result = false;
        if (serverController.isBufferServerServiceRunning()) {
            result = serverController.stopServerService();
        }
        updateConnectionsGui();
    }

    public void stopClients() {
        boolean result = false;
        if (clientsController.isThreadsServiceRunning()) {
            result = clientsController.stopThreadsService();
        }
        updateClientsGui();
    }

    public void onToggleServerSwitch(View view) {
        Switch switchView = (Switch) view;
        if (switchView.isChecked())
            startServer();
        else
            stopServer();
    }

    public void onToggleClientsSwitch(View view) {
        Switch switchView = (Switch) view;
        if (switchView.isChecked())
            startClients();
        else
            stopClients();
    }
}

