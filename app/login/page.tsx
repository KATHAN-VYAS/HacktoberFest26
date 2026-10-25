'use client';
import { useEffect, useState, type FormEvent } from 'react';
export default function Login() {
  const [signup,setSignup]=useState(false),[pending,setPending]=useState(false),[message,setMessage]=useState('');
  useEffect(()=>{if(new URLSearchParams(window.location.search).get('confirmation')==='failed')setMessage('That confirmation link expired or could not be verified. Try signing in if you already confirmed, or request a new confirmation email from the project owner.');},[]);
  async function submit(e:FormEvent<HTMLFormElement>) {
    e.preventDefault();setPending(true);setMessage('');const f=new FormData(e.currentTarget);
    try {
      const response=await fetch('/api/auth',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action:signup?'signup':'signin',email:f.get('email'),password:f.get('password')})});
      const result=await response.json() as {error?:string;confirmationRequired?:boolean};if(!response.ok) throw new Error(result.error||'Please try again.');
      if(result.confirmationRequired) setMessage('Check your email for a confirmation link. After confirming, return here to sign in.');
      else window.location.assign('/');
    } catch(e){setMessage((e as Error).message);} finally {setPending(false);}
  }
  return <main style={{maxWidth:460,margin:'8vh auto',padding:28}}>
    <a href='/' className='text-link'>← Back to TerpCommons</a>
    <h1 style={{fontSize:38,margin:'28px 0 12px'}}>{signup?'Find your people.':'Welcome back, Terp.'}</h1>
    <p style={{marginBottom:24}}>A private account, a public username, and the choice to post anonymously. Incoming students are welcome.</p>
    <form className='stack-form' onSubmit={submit}>
      <label>Email address<input name='email' type='email' autoComplete='email' maxLength={254} required/></label>
      <label>Password<input name='password' type='password' autoComplete={signup?'new-password':'current-password'} minLength={8} maxLength={128} required/></label>
      {message&&<p role='status' className='privacy-note'>{message}</p>}
      <button className='button primary full-width' disabled={pending}>{pending?'One moment…':signup?'Create my account':'Sign in'}</button>
      <button type='button' className='text-link' disabled={pending} onClick={()=>{setSignup(!signup);setMessage('');}}>{signup?'Already a member? Sign in':'New here? Create an account'}</button>
    </form>
    <p className='form-note'>Your email stays private. Student stages are self-reported; UMD enrollment verification is not enabled.</p>
  </main>;
}
