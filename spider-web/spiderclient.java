import java.awt.*;
import java.applet.*;
import java.io.*;
import java.net.*;


public class spiderclient extends Applet {

	public void init() {
		String p;
	
		cf = new spiderframe(this);
		cf.resize(800,600);
		
		p = getParameter("CALL");
		if (p != null) cf.setCall(p);
		
		p = getParameter("FULLNAME");
		if (p != null) cf.setFullname(p);

		p = getParameter("HOSTNAME");
		if (p != null) cf.setHostname(p);		

		p = getParameter("PORT");
		if (p != null) cf.setPort(p);

		p = getParameter("CHANNEL");
		if (p != null) cf.setChannel(p);

		Beep = getAudioClip(getCodeBase(), "ding.au");
		// cf.login();
		cf.resize(655, 380);
		
		cf.show();
	}
	
	public void doconnect() {
		try {
			s = new Socket(cf.getHostname(), Integer.parseInt(cf.getPort()));
			out = new PrintStream(s.getOutputStream());
			in = new DataInputStream(s.getInputStream());
			cf.initPrintStream(out);
		
			listener = new StreamListener(cf, in);
			
			out.println(cf.getCall());
			out.println(cf.getFullname());
		}
		catch (IOException e) { 
			InfoDialog id = new InfoDialog(cf, "Error", e.toString());
		}
		cf.connected();
		Beep.play();
	}

	public void dodisconnect() {
		try {
			s.close();
		}
		catch (IOException e) { 
			InfoDialog id = new InfoDialog(cf, "Error", e.toString());
		}
		cf.disconnected();
		Beep.play();
	}

	void beep() {
		Beep.play();
	}

	private Socket s = null;
	private PrintStream out;
	private DataInputStream in;
	private StreamListener listener;
	
	private AudioClip Beep; 

	spiderframe cf;
}

class StreamListener extends Thread {
	DataInputStream in;
	spiderframe cf;
	
	public StreamListener(spiderframe cf, DataInputStream in) {
		this.in = in;
		this.cf = cf;
		this.start();
	}
	
	public void run() {
		String line;
				
		try {
			for (;;) {
			line = in.readLine();	
			
			// schrieb nur jede 2te zeile , deswegen //
			// line = in.readLine();
			
		        
			
			
			
			if (line == null) break;
				cf.setText(line);
			}
			cf.disconnected();
		}
		catch (IOException e) {
			cf.setText(e.toString());
			cf.disconnected();
		}
		
		finally { cf.setText("Connection closed by server."); }
	}
}
